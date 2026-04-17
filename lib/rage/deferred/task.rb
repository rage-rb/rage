# frozen_string_literal: true

##
# `Rage::Deferred::Task` is a module that should be included in classes that represent tasks to be executed
# in the background by the `Rage::Deferred` queue. It ensures the tasks can be retried in case of a failure,
# with a maximum number of attempts and an exponential backoff strategy.
#
# To define a task, include the module and implement the `#perform` method:
#
# ```ruby
# class ProcessImage
#   include Rage::Deferred::Task
#
#   def perform(image_path:)
#     # logic to process the image
#   end
# end
# ```
#
# The task can be enqueued using the `enqueue` method:
#
# ```ruby
# ProcessImage.enqueue(image_path: 'path/to/image.jpg')
# ```
#
# The `delay` and `delay_until` options can be used to specify when the task should be executed.
#
# ```ruby
# ProcessImage.enqueue(image_path: 'path/to/image.jpg', delay: 10) # delays execution by 10 seconds
# ProcessImage.enqueue(image_path: 'path/to/image.jpg', delay_until: Time.now + 3600) # executes after 1 hour
# ```
#
module Rage::Deferred::Task
  MAX_ATTEMPTS = 5
  private_constant :MAX_ATTEMPTS

  BACKOFF_INTERVAL = 5
  private_constant :BACKOFF_INTERVAL

  # @private
  CONTEXT_KEY = :__rage_deferred_execution_context

  def perform
  end

  # Access metadata for the current task execution.
  # @return [Rage::Deferred::Metadata] the metadata object for the current task execution
  def meta
    Rage::Deferred::Metadata
  end

  # @private
  def __perform(context)
    restore_log_info(context)
    ca_snapshots = restore_current_attributes(context)

    attempts = Rage::Deferred::Context.get_attempts(context)
    task_log_context = { task: self.class.name }
    task_log_context[:attempt] = attempts + 1 if attempts

    Fiber[CONTEXT_KEY] = context

    Rage::Telemetry.tracer.span_deferred_task_process(task: self, context:) do
      Rage::Deferred.__middleware_chain.with_perform_middleware(context, task: self) do
        Rage.logger.with_context(task_log_context) do
          args = Rage::Deferred::Context.get_args(context)
          kwargs = Rage::Deferred::Context.get_kwargs(context)

          perform(*args, **kwargs)
        end
      end
    end

    true
  rescue Exception => e
    unless respond_to?(:__deferred_suppress_exception_logging?, true) && __deferred_suppress_exception_logging?
      Rage.logger.with_context(task_log_context) do
        Rage.logger.error("Deferred task failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      end
    end
    e
  ensure
    # Why reset only what we restored: task fibers are reused by Iodine's worker pool,
    # so leftover Current.* values would poison the next task on the same fiber.
    # But we only need to clean up subclasses whose values we actually set, not every
    # descendant in the app, which would pointlessly fire before_reset/after_reset hooks.
    reset_current_attributes(ca_snapshots) if ca_snapshots
  end

  private def restore_log_info(context)
    log_tags = Rage::Deferred::Context.get_log_tags(context)
    log_context = Rage::Deferred::Context.get_log_context(context)

    if log_tags.is_a?(Array)
      Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context] = log_tags, log_context
    elsif log_tags
      # support the previous format where only `request_id` was passed
      Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context] = [log_tags], {}
    end
  end

  # Why direct attribute assignment and not `CurrentAttributes.set { }`:
  # `set` with a block restores previous values after the block exits. We need
  # the restored values to persist through `perform`, not revert. Rails' own
  # ActiveJob::CurrentAttributes takes the same direct-assign approach.
  #
  # @return [Array, nil] the snapshots we restored, so the ensure block knows what to reset.
  #   Returns nil when there was nothing to do, telling the caller "no cleanup needed."
  private def restore_current_attributes(context)
    snapshots = Rage::Deferred::Context.get_current_attributes(context)
    return nil unless snapshots && !snapshots.empty?

    snapshots.each do |klass, attrs|
      attrs.each { |name, value| klass.public_send("#{name}=", value) }
    rescue => e
      # Why rescue-and-continue: one broken CurrentAttributes subclass must not
      # take down the whole task. Logged so the failure stays visible.
      Rage.logger.warn("Rage::Deferred: failed to restore #{klass}: #{e.class} (#{e.message})")
    end

    snapshots
  end

  # Resets only the subclasses we restored. See the ensure block for why.
  private def reset_current_attributes(snapshots)
    snapshots.each do |klass, _|
      klass.reset
    rescue => e
      Rage.logger.warn("Rage::Deferred: failed to reset #{klass}: #{e.class} (#{e.message})")
    end
  end

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def max_retries(count)
      value = Integer(count)

      if value.negative?
        raise ArgumentError, "max_retries should be a valid non-negative integer"
      end

      @__max_retries = value
    rescue ArgumentError, TypeError
      raise ArgumentError, "max_retries should be a valid non-negative integer"
    end

    def retry_interval(exception, attempt:)
      __default_backoff(attempt)
    end

    def enqueue(*args, delay: nil, delay_until: nil, **kwargs)
      context = Rage::Deferred::Context.build(self, args, kwargs)

      Rage::Telemetry.tracer.span_deferred_task_enqueue(task_class: self, context:) do
        Rage::Deferred.__middleware_chain.with_enqueue_middleware(context, delay:, delay_until:) do
          Rage::Deferred.__queue.enqueue(context, delay:, delay_until:)
        end
      end

      nil
    end

    # @private
    def __next_retry_in(attempts, exception)
      max = @__max_retries || MAX_ATTEMPTS
      return if attempts > max

      interval = retry_interval(exception, attempt: attempts)
      return if !interval

      unless interval.is_a?(Numeric)
        Rage.logger.warn("#{name}.retry_interval returned #{interval.class}, expected Numeric, false, or nil; falling back to default backoff")
        return __default_backoff(attempts)
      end

      interval
    end

    # @private
    def __default_backoff(attempt)
      rand(BACKOFF_INTERVAL * 2**attempt) + 1
    end
  end
end

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
  MAX_ATTEMPTS = 20
  private_constant :MAX_ATTEMPTS

  # @private
  CONTEXT_KEY = :__rage_deferred_execution_context

  # @private
  RETRY_IN_CACHE_KEY = :__rage_deferred_retry_in
  private_constant :RETRY_IN_CACHE_KEY

  def perform
  end

  # Access metadata for the current task execution.
  # @return [Rage::Deferred::Metadata] the metadata object for the current task execution
  # @example
  #   class MyTask
  #     include Rage::Deferred::Task
  #
  #     def perform
  #       puts meta.retries
  #     end
  #   end
  def meta
    Rage::Deferred::Metadata
  end

  # @private
  def __perform(context)
    restore_log_info(context)

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
    Rage::Errors.report(e)

    unless respond_to?(:__deferred_suppress_exception_logging?, true) && __deferred_suppress_exception_logging?
      Rage.logger.with_context(task_log_context) do
        Rage.logger.error("Deferred task failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      end
    end
    e
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

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    # Set the maximum number of retry attempts for this task.
    #
    # @param count [Integer] the maximum number of retry attempts
    # @example
    #   class SendWelcomeEmail
    #     include Rage::Deferred::Task
    #     max_retries 10
    #
    #     def perform(email)
    #       # ...
    #     end
    #   end
    def max_retries(count)
      value = Integer(count)

      if value.negative?
        raise ArgumentError, "max_retries should be a valid non-negative integer"
      end

      @__max_retries = value
    rescue ArgumentError, TypeError
      raise ArgumentError, "max_retries should be a valid non-negative integer"
    end

    # Override this method to customize retry behavior per exception.
    #
    # Return an Integer to retry in that many seconds.
    # Return `super` to use the default exponential backoff.
    # Return `false` or `nil` to abort retries.
    #
    # @param exception [Exception] the exception that caused the failure
    # @param attempt [Integer] the current attempt number (1-indexed)
    # @return [Integer, false, nil] the retry interval in seconds, or false/nil to abort
    # @example
    #   class ProcessPayment
    #     include Rage::Deferred::Task
    #
    #     def self.retry_interval(exception, attempt:)
    #       case exception
    #       when TemporaryNetworkError
    #         10 # Retry in 10 seconds
    #       when InvalidDataError
    #         false # Do not retry
    #       else
    #         super # Default backoff strategy
    #       end
    #     end
    #
    #     def perform(payment_id)
    #       # ...
    #     end
    #   end
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
      cached = Fiber[RETRY_IN_CACHE_KEY]
      if cached && cached[0] == attempts
        return cached[1]
      end

      max = @__max_retries || MAX_ATTEMPTS
      return __cache_retry_in(attempts, nil) if attempts > max

      interval = retry_interval(exception, attempt: attempts)
      return __cache_retry_in(attempts, nil) if !interval

      unless interval.is_a?(Numeric)
        Rage.logger.warn("#{name}.retry_interval returned #{interval.class}, expected Numeric, false, or nil; falling back to default backoff")
        return __cache_retry_in(attempts, __default_backoff(attempts))
      end

      __cache_retry_in(attempts, interval)
    end

    # @private
    def __cache_retry_in(attempts, value)
      Fiber[RETRY_IN_CACHE_KEY] = [attempts, value]
      value
    end

    # @private
    def __default_backoff(attempt)
      (attempt**4) + 10 + (rand(15) * attempt)
    end
  end
end

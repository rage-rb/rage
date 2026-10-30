# frozen_string_literal: true

##
# A dead task is a deferred task that is no longer retried. Use this object to read the stored
# information about the task, to delete the task with {#delete}, or to enqueue it again with {#retry}.
#
# The attributes and {#delete} work even when the task class no longer exists or the arguments
# cannot be decoded. Only {#args}, {#kwargs}, and {#retry} need them.
#
# Do not serialize this object with `Marshal`, for example as an argument of a deferred task.
# Pass its {#id} instead, and find the task again with {Rage::Deferred::DeadTasks#find_by_id}.
#
class Rage::Deferred::DeadTask
  # @return [String] the ID that Rage assigned when it enqueued the task
  attr_reader :id

  # @return [String] the name of the task class
  attr_reader :task_class

  # @return [Integer] the number of processing attempts
  attr_reader :attempts

  # @return [Time] the time when Rage enqueued the task
  attr_reader :enqueued_at

  # @return [Time] the time when the last attempt failed
  attr_reader :failed_at

  # @return [String] the class name of the last exception
  attr_reader :exception_class

  # @return [String] the message from the last exception
  attr_reader :exception_message

  # @return [Array<String>] the frozen backtrace from the last exception
  attr_reader :backtrace

  # @private
  def initialize(record, backend)
    @id = record[:id].dup.freeze
    @task_class = record[:task_class].dup.freeze
    @attempts = record[:attempts]
    @enqueued_at = Time.at(record[:enqueued_at])
    @failed_at = Time.at(record[:failed_at])

    @exception_class = record[:exception_class].dup.freeze
    @exception_message = record[:exception_message].dup.freeze
    @backtrace = record[:backtrace].map { |line| line.dup.freeze }.freeze
    @__context = record[:context].dup.freeze
    @__backend = backend
  end

  # Permanently delete the task.
  #
  # The method returns `true` when it deletes the task and `false` when the task no longer exists,
  # for example because another process already deleted or retried it.
  #
  # To delete many tasks, pass their IDs to one {Rage::Deferred::DeadTasks#delete} call.
  #
  # When the method raises, the task may or may not be deleted.
  #
  # @return [Boolean] true when the task was removed, otherwise false
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when the store cannot be locked
  # @raise [SystemCallError] when a storage operation fails
  # @example Delete one task
  #   Rage::Deferred.dead_tasks.find_by_id("1735689600-12345-1")&.delete
  def delete
    @__backend.remove_dead_tasks(@id) == 1
  end

  # Enqueue the task again with its original arguments, then remove it from the dead tasks.
  #
  # The new task gets a new ID and starts with no previous attempts.
  # The new task is enqueued before the dead task is removed: a failure between the two steps can
  # leave the task in both places. A successful retry does not guarantee that the task survives every crash.
  #
  # An enqueue middleware that does not call `yield` rejects the new task, as documented for enqueue middleware.
  # `retry` still removes the dead task and returns `true`.
  #
  # Tasks must be idempotent: deferred tasks run at least once, so a retried task can run twice.
  # The enqueue middleware runs again for the new task, so it must be safe to run twice on the same arguments.
  #
  # Outside a running server (for example, in the console or in a Rake task), the new task does not
  # run in this process.
  #
  # @return [Boolean] true when the task was enqueued again; false when the dead task no longer exists
  # @raise [Rage::Deferred::DeadTaskRetryError] when the task class does not exist or is not a deferred
  #   task, or when the dead task cannot be removed after the new task was enqueued
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the stored arguments cannot be decoded
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when the store cannot be locked
  # @raise [Rage::Deferred::PushTimeout] when backpressure is enabled and the queue stays full for too long
  # @raise [SystemCallError] when lookup or synchronization fails
  # @example Retry the dead tasks of one task class
  #   Rage::Deferred.dead_tasks.each { |task| task.retry if task.task_class == "SendWelcomeEmail" }
  # @example Retry one task when only its ID is known
  #   Rage::Deferred.dead_tasks.find_by_id("1735689600-12345-1")&.retry
  def retry
    return false unless @__backend.find_dead_task(@id)

    task_class = resolve_task_class
    args, kwargs = decode_task_arguments
    task_class.enqueue(*args, **kwargs)

    @__backend.flush_tasks if @__backend.respond_to?(:flush_tasks)
    warn "Dead task #{@id} was retried; server restart is required." unless Iodine.running?

    begin
      @__backend.remove_dead_tasks(@id)
    rescue => e
      raise Rage::Deferred::DeadTaskRetryError.new(
        "Could not remove dead task #{@id} after retry; work may exist in both stores"
      ), cause: e
    end

    true
  end

  # Return the original positional arguments.
  #
  # The Array and all objects in it are frozen.
  # When the task was enqueued without positional arguments, the method returns an empty Array.
  #
  # @return [Array] frozen positional arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the stored arguments cannot be decoded
  def args
    decode_context unless defined?(@__args)
    @__args
  end

  # Return the original keyword arguments.
  #
  # The Hash and all objects in it are frozen.
  # When the task was enqueued without keyword arguments, the method returns an empty Hash.
  #
  # @return [Hash] frozen keyword arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the stored arguments cannot be decoded
  def kwargs
    decode_context unless defined?(@__kwargs)
    @__kwargs
  end

  private

  # @private
  def resolve_task_class
    begin
      task_class = Object.const_get(@task_class, false)
    rescue NameError => e
      raise Rage::Deferred::DeadTaskRetryError.new(
        "Could not resolve task class for dead task #{@id}"
      ), cause: e
    end

    unless task_class.is_a?(Class) && task_class.include?(Rage::Deferred::Task)
      raise Rage::Deferred::DeadTaskRetryError, "Invalid task class for dead task #{@id}"
    end

    task_class
  end

  # @private
  def decode_task_arguments
    context = Marshal.load(@__context)
    args = Rage::Deferred::Context.get_args(context)
    kwargs = Rage::Deferred::Context.get_kwargs(context)
    [args.nil? ? [] : args, kwargs.nil? ? {} : kwargs]
  rescue => e
    raise Rage::Deferred::DeadTaskContextDeserializationError.new(
      "Could not deserialize execution context for dead task #{@id}"
    ), cause: e
  end

  # @private
  def decode_context
    context = Marshal.load(@__context, freeze: true)
    args = Rage::Deferred::Context.get_args(context)
    kwargs = Rage::Deferred::Context.get_kwargs(context)
    args = [].freeze if args.nil?
    kwargs = {}.freeze if kwargs.nil?

    @__args = args
    @__kwargs = kwargs
  rescue => e
    error = Rage::Deferred::DeadTaskContextDeserializationError.new(
      "Could not deserialize execution context for dead task #{@id}"
    )
    raise error, cause: e
  end

  private_class_method :new
end

# frozen_string_literal: true

##
# A dead task is a deferred task that is no longer retried.
# Creating this object does not load the task class.
# The first call to {#args} or {#kwargs} deserializes the execution context.
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
    @backend = backend
  end

  # Permanently delete the task.
  #
  # The method returns `true` when it deletes the task and `false` when the task no longer exists.
  # Deleting a task does not change the active enumeration.
  # The method may raise storage-related errors.
  #
  # @return [Boolean] true when the task was removed, otherwise false
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when the store cannot be locked
  # @raise [SystemCallError] when a storage operation fails
  def delete
    @backend.remove_dead_tasks(@id) == 1
  end

  # Enqueue a fresh copy of the task, then remove the dead record.
  #
  # Retry checks that the record exists and calls public `enqueue` with the entry's original stored arguments.
  # The new task starts with a fresh ID and no previous retry attempts.
  # Retry makes sure pending writes are durable before removing the task from dead-task storage.
  #
  # Middleware or telemetry can skip enqueue without raising; retry still deletes the dead record and returns `true`.
  #
  # @return [Boolean] true when the sequence completes; false when lookup returns no record
  # @raise [Rage::Deferred::DeadTaskRetryError] when class resolution or removal fails
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the context cannot be decoded
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when the store cannot be locked
  # @raise [SystemCallError] when lookup or synchronization fails
  def retry
    return false unless @backend.find_dead_task(@id)

    task_class = resolve_task_class
    args, kwargs = decode_task_arguments
    task_class.enqueue(*args, **kwargs)

    @backend.flush if @backend.respond_to?(:flush)
    warn "Dead task #{@id} was retried; server restart is required." unless Iodine.running?

    begin
      @backend.remove_dead_tasks(@id)
    rescue => e
      raise Rage::Deferred::DeadTaskRetryError.new(
        "Could not remove dead task #{@id} after retry; work may exist in both stores"
      ), cause: e
    end

    true
  end

  # Return the original positional arguments.
  #
  # On the first call, the method deserializes the execution context.
  # The method freezes all objects in the decoded data.
  # After a successful call, the method returns the same Array on each later call.
  # If the stored value is `nil`, the method returns a frozen empty Array.
  #
  # @return [Array] frozen positional arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the context cannot be decoded
  def args
    decode_context unless defined?(@__args)
    @__args
  end

  # Return the original keyword arguments.
  #
  # On the first call, the method deserializes the execution context.
  # The method freezes all objects in the decoded data.
  # After a successful call, the method returns the same Hash on each later call.
  # If the stored value is `nil`, the method returns a frozen empty Hash.
  #
  # @return [Hash] frozen keyword arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the context cannot be decoded
  def kwargs
    decode_context unless defined?(@__kwargs)
    @__kwargs
  end

  private

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

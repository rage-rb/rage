# frozen_string_literal: true

##
# Provides information about one dead task.
#
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
  def initialize(record)
    @id = record[:id].dup.freeze
    @task_class = record[:task_class].dup.freeze
    @attempts = record[:attempts]
    @enqueued_at = Time.at(record[:enqueued_at])
    @failed_at = Time.at(record[:failed_at])

    @exception_class = record[:exception_class].dup.freeze
    @exception_message = record[:exception_message].dup.freeze
    @backtrace = record[:backtrace].map { |line| line.dup.freeze }.freeze
    @__context = record[:context].dup.freeze
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

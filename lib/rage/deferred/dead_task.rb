# frozen_string_literal: true

##
# A read-only view of a deferred task that used all its retries or stopped retrying.
#
# Values come from trusted local dead-task storage.
# Reading metadata does not load the task class or deserialize the stored execution context.
# {#args} and {#kwargs} load the context only when you call them.
# The context is trusted local Marshal data.
# Argument data can contain credentials or personal data. Protect this data from unauthorized access.
class Rage::Deferred::DeadTask
  # @return [String] the task's persisted identifier
  attr_reader :id

  # @return [String] the stored task class name
  attr_reader :task_class

  # @return [Integer] the number of attempts to process the task
  attr_reader :attempts

  # @return [Time] the time encoded in the task's persisted identifier
  attr_reader :enqueued_at

  # @return [Time] the time when the final attempt failed
  attr_reader :failed_at

  # @return [String] the stored class name of the final exception
  attr_reader :exception_class

  # @return [String] the stored message of the final exception
  attr_reader :exception_message

  # @return [Array<String>] the frozen stored backtrace of the final exception
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
  # The first successful call decodes the trusted local Marshal context.
  # The method freezes the decoded object graph and returns the same Array on later calls.
  # Changes to the returned Array cannot change the stored replay input.
  # A stored `nil` produces an empty Array.
  # The method does not cache a decoding failure.
  # You can try again after you restore the application constants.
  #
  # Argument data can contain credentials or personal data. Protect this data from unauthorized access.
  #
  # @return [Array] frozen positional arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the context cannot be decoded
  def args
    decode_context unless defined?(@__args)
    @__args
  end

  # Return the original keyword arguments.
  #
  # The first successful call decodes the trusted local Marshal context.
  # The method freezes the decoded object graph and returns the same Hash on later calls.
  # Changes to the returned Hash cannot change the stored replay input.
  # A stored `nil` produces an empty Hash.
  # This behavior keeps positional and keyword arguments separate on Ruby 3.3.
  # The method does not cache a decoding failure.
  # You can try again after you restore the application constants.
  #
  # Argument data can contain credentials or personal data. Protect this data from unauthorized access.
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

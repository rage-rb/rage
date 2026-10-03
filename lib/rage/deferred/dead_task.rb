# frozen_string_literal: true

##
# A read-only view of a deferred task that exhausted or aborted its retries.
#
# Values come from trusted local dead-task storage. Reading metadata does not
# resolve the task class or deserialize its stored execution context. Calling
# {#args} or {#kwargs} lazily loads that context as trusted local Marshal data.
# Argument data can contain credentials or personal data and should be handled
# accordingly.
class Rage::Deferred::DeadTask
  # @return [String] the task's persisted identifier
  attr_reader :id

  # @return [String] the stored task class name
  attr_reader :task_class

  # @return [Integer] the number of attempts made before the task was abandoned
  attr_reader :attempts

  # @return [Time] the time encoded in the task's persisted identifier
  attr_reader :enqueued_at

  # @return [Time] the time at which the final attempt failed
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
    @enqueued_at = Time.at(record[:enqueued_at]).freeze
    @failed_at = Time.at(record[:failed_at]).freeze

    @exception_class = record[:exception_class].dup.freeze
    @exception_message = record[:exception_message].dup.freeze
    @backtrace = record[:backtrace].map { |line| line.dup.freeze }.freeze
    @__context = record[:context].dup.freeze
  end

  # Return the original positional arguments.
  #
  # The trusted local Marshal context is decoded only on the first successful
  # detailed read. The returned graph is frozen, is shared by repeated reads,
  # and cannot mutate the stored replay input. A stored `nil` is normalized to
  # an empty Array. Failed decoding is not cached, so access can be retried if
  # application constants are restored.
  #
  # Argument data may contain credentials or personal data.
  #
  # @return [Array] frozen positional arguments
  # @raise [Rage::Deferred::DeadTaskContextDeserializationError] when the context cannot be decoded
  def args
    decode_context unless defined?(@__args)
    @__args
  end

  # Return the original keyword arguments.
  #
  # The trusted local Marshal context is decoded only on the first successful
  # detailed read. The returned graph is frozen, is shared by repeated reads,
  # and cannot mutate the stored replay input. A stored `nil` is normalized to
  # an empty Hash, preserving positional and keyword separation on Ruby 3.3.
  # Failed decoding is not cached, so access can be retried if application
  # constants are restored.
  #
  # Argument data may contain credentials or personal data.
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
    raise TypeError, "dead-task context must be an Array" unless context.is_a?(Array)
    raise TypeError, "dead-task context is missing argument fields" if context.length < 3

    args = context[1]
    kwargs = context[2]
    args = [].freeze if args.nil?
    kwargs = {}.freeze if kwargs.nil?
    raise TypeError, "dead-task positional arguments must be an Array" unless args.is_a?(Array)
    raise TypeError, "dead-task keyword arguments must be a Hash" unless kwargs.is_a?(Hash)

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

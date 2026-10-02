# frozen_string_literal: true

##
# A read-only summary of a deferred task that exhausted or aborted its retries.
#
# Summary values come from trusted local dead-task storage. Listing a dead task
# does not resolve its task class or deserialize its stored execution context.
# Strings and timestamps are frozen so callers cannot mutate the stored summary
# through this object.
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

  # @private
  def initialize(record)
    @id = record[:id].dup.freeze
    @task_class = record[:task_class].dup.freeze
    @attempts = record[:attempts]
    @enqueued_at = Time.at(record[:enqueued_at]).freeze
    @failed_at = Time.at(record[:failed_at]).freeze

    # Retain defensive copies of the remaining stored fields for the detailed
    # inspection API added by the next task. They are intentionally not public
    # in the listing-only API.
    @__exception_class = record[:exception_class].dup.freeze
    @__exception_message = record[:exception_message].dup.freeze
    @__backtrace = record[:backtrace].map { |line| line.dup.freeze }.freeze
    @__context = record[:context].dup.freeze
  end

  private_class_method :new
end

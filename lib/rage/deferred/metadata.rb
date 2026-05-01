# frozen_string_literal: true

##
# Provides metadata about the current deferred task execution.
#
class Rage::Deferred::Metadata
  class << self
    # Returns the current attempt number.
    # @return [Integer] the current attempt number (1 for the first run)
    def attempts
      Rage::Deferred::Context.get_attempts(context).to_i + 1
    end

    # Returns the number of retries that have occurred for the current task.
    # @return [Integer] the number of retries (0 on first run, 1+ on retries)
    def retries
      attempts - 1
    end

    # Checks whether this is a retry execution.
    # @return [Boolean] `true` if this is a retry, `false` if this is the first run
    def retrying?
      attempts > 1
    end

    # Checks whether the task will be retried if the current execution fails.
    # @return [Boolean] `true` if a failure will schedule another attempt, `false` otherwise
    def will_retry?
      task = Rage::Deferred::Context.get_task(context)
      !!task.__next_retry_in(attempts, nil)
    end

    # Returns the number of seconds until the next retry, or `nil` if no retry will occur.
    # The result is memoized per attempt so that the value reported here matches what the queue uses to schedule the retry.
    # @return [Numeric, nil] retry delay in seconds, or `nil` if the task won't be retried
    def will_retry_in
      task = Rage::Deferred::Context.get_task(context)
      task.__next_retry_in(attempts, nil)
    end

    private

    def context
      Fiber[Rage::Deferred::Task::CONTEXT_KEY]
    end
  end
end

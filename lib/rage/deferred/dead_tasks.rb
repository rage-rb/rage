# frozen_string_literal: true

##
# The collection of deferred tasks that used all their retries or stopped retrying.
#
# The first call to {Rage::Deferred.dead_tasks} creates a collection wrapper around the configured backend.
# Later calls return the same wrapper.
# The wrapper uses the same backend object as the deferred queue.
# The wrapper does not keep traversal state.
# Each traversal requests records from the configured backend.
class Rage::Deferred::DeadTasks
  include Enumerable

  # @private
  def initialize(backend)
    @backend = backend
  end

  # Call the block for each read-only dead-task summary. Start with the oldest task.
  #
  # Without a block, this method returns a standard lazy Ruby Enumerator.
  #
  # @yieldparam dead_task [Rage::Deferred::DeadTask] a read-only task summary
  # @return [Enumerator, self] a new Enumerator without a block, otherwise this collection
  def each
    return enum_for(__method__) unless block_given?

    @backend.each_dead_task do |record|
      yield Rage::Deferred::DeadTask.send(:new, record)
    end

    self
  end

  # Return the dead task with the exact persisted ID.
  #
  # The ID must be a String. The method does not convert other values to a String.
  # The method does not load the stored task class or deserialize its execution context.
  #
  # @param id [String] the exact persisted task ID
  # @return [Rage::Deferred::DeadTask, nil] the matching task, or nil
  # @raise [TypeError] when the ID is not a String
  def find_by_id(id)
    raise TypeError, "dead task id must be a String" unless id.is_a?(String)

    record = @backend.find_dead_task(id)
    Rage::Deferred::DeadTask.send(:new, record) if record
  end
end

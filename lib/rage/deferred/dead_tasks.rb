# frozen_string_literal: true

##
# Provides access to deferred tasks that Rage no longer retries.
#
# {Rage::Deferred.dead_tasks} returns this collection.
class Rage::Deferred::DeadTasks
  include Enumerable

  # @private
  def initialize(backend)
    @backend = backend
  end

  # Yield each dead task from oldest to newest.
  #
  # Without a block, the method returns a new Enumerator.
  #
  # @yieldparam dead_task [Rage::Deferred::DeadTask] information about one dead task
  # @return [Enumerator, self] a new Enumerator without a block, or this collection with a block
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

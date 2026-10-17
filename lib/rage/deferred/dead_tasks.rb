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
      yield build_entry(record)
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
    build_entry(record) if record
  end

  # Permanently delete one or more dead tasks.
  #
  # Pass one String ID or one flat Array of String IDs; the method returns the number of deleted tasks.
  #
  # @param id_or_ids [String, Array<String>] one exact ID or one flat Array of exact IDs
  # @return [Integer] the number of distinct tasks that were removed
  # @raise [ArgumentError] when the call does not contain exactly one argument
  # @raise [TypeError] when the argument is not a String or a flat Array of Strings
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when the store cannot be locked
  # @raise [SystemCallError] when a storage operation fails
  # @example Delete one task
  #   Rage::Deferred.dead_tasks.delete("1735689600-12345-1")
  # @example Delete tasks whose last attempt failed more than 30 days ago
  #   cutoff = Time.now - 30 * 24 * 60 * 60
  #   ids = Rage::Deferred.dead_tasks.filter_map { |task| task.id if task.failed_at < cutoff }
  #   Rage::Deferred.dead_tasks.delete(ids)
  def delete(id_or_ids)
    ids = id_or_ids.is_a?(Array) ? id_or_ids : [id_or_ids]
    raise TypeError, "dead task ids must be Strings" unless ids.all?(String)
    return 0 if ids.empty?

    @backend.remove_dead_tasks(ids.uniq)
  end

  private

  # @private
  def build_entry(record)
    Rage::Deferred::DeadTask.send(:new, record, @backend)
  end
end

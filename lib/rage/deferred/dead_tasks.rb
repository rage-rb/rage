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

  # Return the dead task with the given ID.
  #
  # The ID must be a String. The method does not convert other values to a String.
  #
  # @param id [String] the task ID, as returned by {Rage::Deferred::DeadTask#id}
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
  # The method counts each distinct ID once. IDs that do not exist, or that another process has already
  # deleted, are not errors and are not counted. An empty Array returns `0`.
  #
  # If any ID is invalid, the method raises and deletes nothing.
  # IDs are not converted: pass the exact `id` Strings of the dead tasks.
  #
  # To delete many tasks, collect their IDs and pass them in one call, as in the example below,
  # instead of calling {Rage::Deferred::DeadTask#delete} for each task.
  #
  # When two calls name the same ID, only the call that runs first counts it. Deleting a task does not
  # stop work that a retry of the same task has already enqueued.
  #
  # When the method raises, some of the tasks may already be deleted.
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

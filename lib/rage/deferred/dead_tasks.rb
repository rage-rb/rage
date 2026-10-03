# frozen_string_literal: true

##
# The collection of deferred tasks that exhausted or aborted their retries.
#
# {Rage::Deferred.dead_tasks} memoizes this collection and gives it the same
# backend used by the deferred queue. The collection stores no traversal state.
#
# Each block traversal or top-level Enumerable operation (`first`, `find`,
# `each`, and others) gets a fresh stable snapshot and a temporary winner index.
# The index is discarded when that operation ends; it is never cached or shared.
#
# On Disk, traversal scans the complete snapshot before its first yield, selects
# the newest valid record for each task ID, and yields the selected tasks
# oldest-first.
#
# Block traversal and normally unwound terminal Enumerable operations clean up
# automatically. An abandoned, partly consumed Enumerator may keep its file
# descriptor open until Ruby unwinds or garbage-collects it.
#
# Invalid records are skipped silently. Lock and filesystem errors propagate
# unchanged. Records can contain sensitive application and exception data, so
# redact them before copying their contents into logs or tickets.
class Rage::Deferred::DeadTasks
  include Enumerable

  # @private
  def initialize(backend)
    @backend = backend
  end

  # Yield read-only dead-task summaries oldest-first.
  #
  # Without a block, this method returns a normal lazy Ruby Enumerator. Prefer
  # block traversal when prompt cleanup matters.
  #
  # @yieldparam dead_task [Rage::Deferred::DeadTask] a passive task summary
  # @return [Enumerator, self] a new Enumerator without a block, otherwise this collection
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when snapshot acquisition cannot obtain the store lock
  # @raise [SystemCallError] when opening, reading, seeking, or closing the snapshot fails
  def each
    return enum_for(__method__) unless block_given?

    @backend.each_dead_task do |record|
      yield Rage::Deferred::DeadTask.send(:new, record)
    end

    self
  end

  # Find the newest frame-valid dead task with an exact persisted ID.
  #
  # The ID must be a String and is never coerced. Lookup does not resolve the
  # stored task class or deserialize its execution context. On Disk, recoverable
  # corrupt records are skipped silently; lock and filesystem errors propagate
  # unchanged. Backend-specific lookup complexity is not part of this API.
  #
  # @param id [String] exact persisted task identifier
  # @return [Rage::Deferred::DeadTask, nil] the matching task, or nil
  # @raise [TypeError] when id is not a String
  # @raise [Rage::Deferred::DeadTasksLockTimeout] when snapshot acquisition cannot obtain the store lock
  # @raise [SystemCallError] when opening, reading, seeking, or closing the snapshot fails
  def find_by_id(id)
    raise TypeError, "dead task id must be a String" unless id.is_a?(String)

    record = @backend.find_dead_task(id)
    Rage::Deferred::DeadTask.send(:new, record) if record
  end
end

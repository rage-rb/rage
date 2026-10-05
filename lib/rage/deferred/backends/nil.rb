# frozen_string_literal: true

class Rage::Deferred::Backends::Nil
  def initialize(**)
  end

  def add_task(_, **)
  end

  def remove_task(_)
  end

  def pending_tasks
    []
  end

  def add_dead_task(_, _, _, **)
  end

  # Yield no dead-task records.
  # @return [self]
  # @private
  def each_dead_task
    self
  end

  # Return no dead task for an exact ID lookup.
  # @param _ [String] the persisted task ID
  # @return [nil]
  # @private
  def find_dead_task(_)
  end

  def remove_dead_tasks(_)
    0
  end
end

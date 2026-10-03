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

  # @private
  def each_dead_task
    self
  end

  # @private
  def find_dead_task(_)
  end

  def remove_dead_tasks(_)
    0
  end
end

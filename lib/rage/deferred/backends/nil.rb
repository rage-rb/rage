# frozen_string_literal: true

class Rage::Deferred::Backends::Nil
  def initialize(**)
  end

  def add(_, **)
  end

  def remove(_)
  end

  def pending_tasks
    []
  end
end

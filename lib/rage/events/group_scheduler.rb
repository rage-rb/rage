# frozen_string_literal: true

##
# The class manages processing grouped fibers one after another. It ensures that groups of fibers are processed
# sequentially, while fibers inside a specific group can still be processed concurently.
# It's used to coordinate a swarm of `Rage::Events::GroupTask` tasks and is based on an assumption
# that fibers request to enter a group sequentially. I.e. for the ordered events (`x`, `y`), we assume that
# the fibers processing the `y` subscribers will request to enter a group only after the `x` subscribers.
#
class Rage::Events::GroupScheduler
  class << self
    def instances
      @instances ||= {}
    end

    def instance(id)
      instances[id] ||= new(id)
    end

    def remove_instance(id)
      instances.delete(id)
    end
  end

  # @param instance_id [Object] id of the current singleton scheduler instance
  def initialize(instance_id)
    @instance_id = instance_id

    @lock_groups = Hash.new { |hash, key| hash[key] = Set.new }
    @blocked = []
  end

  # Request to enter a group. The method will block if another group is currently being processed.
  # @param group [Object] the identifier of a group current fiber belongs to
  # @param resource [Object] the unique identifier of the blocked resource
  # @note we can't use fibers as a resource because retries happen in different fibers
  def enter(group:, resource:)
    while @lock_groups.any? && !@lock_groups.has_key?(group)
      @blocked << Fiber.current
      Rage::Deferred.__queue.pause
    end

    @lock_groups[group] << resource
  end

  # Notify the scheduler the fiber has finished executing.
  # @param group [Object] the identifier of a group current fiber belongs to
  # @param resource [Object] the unique identifier of the blocked resource
  def exit(group:, resource:)
    @lock_groups[group].delete(resource)

    if @lock_groups[group].empty?
      @lock_groups.delete(group)

      if @blocked.any? && !Iodine.stopping?
        blocked_fibers = @blocked.dup
        @blocked.clear
        Iodine.defer { blocked_fibers.each { |f| Rage::Deferred.__queue.resume(f) } }
      end
    end

    self.class.remove_instance(@instance_id) if @lock_groups.empty?
  end

  def has_resources?(group:)
    @lock_groups.has_key?(group)
  end
end

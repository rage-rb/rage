# frozen_string_literal: true

class Rage::Deferred::Scheduler
  LOCK_PATH = "/tmp/rage_deferred_scheduler.lock"

  def self.start(tasks)
    return if tasks.empty?

    elect_leader { register_timers(tasks) }
  end

  def self.elect_leader(&block)
    @lock ||= File.open(LOCK_PATH, File::WRONLY | File::CREAT, 0o644)

    if @lock.flock(File::LOCK_EX | File::LOCK_NB)
      if Rage.logger.debug?
        puts "INFO: #{Process.pid} is managing scheduled tasks"
      end
      block.call
    end
  end

  def self.register_timers(tasks)
    tasks.each do |entry|
      Iodine.run_every((entry[:interval] * 1000).to_i) do
        entry[:task].enqueue
      end
    end
  end
end

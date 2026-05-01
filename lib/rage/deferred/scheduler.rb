# frozen_string_literal: true

class Rage::Deferred::Scheduler
  LOCK_PATH = "/tmp/rage_deferred_scheduler.lock"

  def self.start(tasks)
    return if tasks.empty?

    Rage::Internal.pick_a_worker(lock_path: LOCK_PATH) do
      Rage.logger.info " Worker PID #{Process.pid} is managing scheduled tasks"
      register_timers tasks
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

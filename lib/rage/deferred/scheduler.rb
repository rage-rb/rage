# frozen_string_literal: true

# @private
class Rage::Deferred::Scheduler
  LOCK_PATH = "/tmp/rage_deferred_scheduler.lock"

  def self.start(tasks)
    return if tasks.empty?

    Rage::Internal.pick_a_worker(lock_path: LOCK_PATH) do
      puts("INFO: #{Process.pid} is managing scheduled tasks.") if Rage.logger.info?
      register_timers(tasks)
    end
  end

  def self.register_timers(tasks)
    tasks.each do |entry|
      interval = (entry[:interval] * 1000).to_i

      if Rage.env.development?
        Iodine.run_every(interval) { Object.const_get(entry[:task].name).enqueue }
      else
        Iodine.run_every(interval) { entry[:task].enqueue }
      end
    end
  end
end

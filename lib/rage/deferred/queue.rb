# frozen_string_literal: true

class Rage::Deferred::Queue
  def initialize(backend)
    @backend = backend
  end

  # Write the task to the storage and schedule it for execution.
  def enqueue(task, delay: nil, delay_until: nil, attempts: nil, task_id: nil)
    publish_in, publish_at = if delay
      delay_i = delay.to_i
      [delay_i, Time.now.to_i + delay_i] if delay_i > 0
    elsif delay_until
      delay_until_i, current_time_i = delay_until.to_i, Time.now.to_i
      [delay_until_i - current_time_i, delay_until_i] if delay_until_i > current_time_i
    end

    persisted_task_id = @backend.add(task, publish_at:, attempts:, task_id:)
    schedule(persisted_task_id, task, publish_in:, attempts:)
  end

  # Schedule the task for execution.
  def schedule(task_id, task, publish_in: nil, attempts: nil)
    publish_in_ms = publish_in.to_i * 1_000 if publish_in && publish_in > 0

    Iodine.run_after(publish_in_ms) do
      unless Iodine.stop_requested?
        Fiber.schedule do
          Iodine.task_inc!
          task.perform
        rescue Exception => e
          attempts = attempts.to_i + 1
          if task.__should_retry?(attempts)
            enqueue(task, delay: task.__next_retry_in(attempts), attempts:, task_id:)
          else
            @backend.remove(task_id)
          end
          Rage.logger.error("#{task.class} deferred task failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        else
          @backend.remove(task_id)
        ensure
          Iodine.task_dec!
        end
      end
    end
  end
end

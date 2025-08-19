# frozen_string_literal: true

class Rage::Deferred::Queue
  attr_reader :backlog_size

  def initialize(backend)
    @backend = backend
    @backlog_size = 0
    @backpressure = Rage.config.deferred.backpressure
  end

  # Write the task to the storage and schedule it for execution.
  def enqueue(task_metadata, delay: nil, delay_until: nil, task_id: nil)
    apply_backpressure if @backpressure

    publish_in, publish_at = if delay
      delay_i = delay.to_i
      [delay_i, Time.now.to_i + delay_i] if delay_i > 0
    elsif delay_until
      delay_until_i, current_time_i = delay_until.to_i, Time.now.to_i
      [delay_until_i - current_time_i, delay_until_i] if delay_until_i > current_time_i
    end

    persisted_task_id = @backend.add(task_metadata, publish_at:, task_id:)
    schedule(persisted_task_id, task_metadata, publish_in:)
  end

  # Schedule the task for execution.
  def schedule(task_id, task_metadata, publish_in: nil)
    publish_in_ms = publish_in.to_i * 1_000 if publish_in && publish_in > 0
    task = Rage::Deferred::Metadata.get_task(task_metadata)
    @backlog_size += 1 unless publish_in_ms

    Iodine.run_after(publish_in_ms) do
      @backlog_size -= 1 unless publish_in_ms

      unless Iodine.stopping?
        Fiber.schedule do
          Iodine.task_inc!

          is_completed = task.new.__perform(task_metadata)

          if is_completed
            @backend.remove(task_id)
          else
            attempts = Rage::Deferred::Metadata.inc_attempts(task_metadata)
            if task.__should_retry?(attempts)
              enqueue(task_metadata, delay: task.__next_retry_in(attempts), task_id:)
            else
              @backend.remove(task_id)
            end
          end

        ensure
          Iodine.task_dec!
        end
      end
    end
  end

  private

  def apply_backpressure
    if @backlog_size > @backpressure.high_water_mark && !Fiber[:rage_backpressure_applied]
      Fiber[:rage_backpressure_applied] = true

      i, target_backlog_size = 0, @backpressure.low_water_mark
      while @backlog_size > target_backlog_size && i < @backpressure.timeout_iterations
        sleep @backpressure.sleep_interval
        i += 1
      end

      if i == @backpressure.timeout_iterations
        raise Rage::Deferred::PushTimeout, "could not enqueue deferred task within #{@backpressure.timeout} seconds"
      end
    end
  end
end

# frozen_string_literal: true

# @private
# This is an in-progress PoC component
class Rage::Signal
  class << self
    def __signals
      @__signals ||= Hash.new do |h, k|
        h[k] = Hash.new { |h_in, k_in| h_in[k_in] = Set.new }
      end
    end

    def __subscriptions
      @__subscriptions ||= Hash.new { |h, k| h[k] = {} }
    end

    def on(signal_id, subscription_id, &block)
      if __subscriptions.has_key?(signal_id) && __subscriptions[signal_id].has_key?(subscription_id)
        raise ArgumentError, "subscription already exists"
      end

      signal_worker = build_signal_worker

      __signals[signal_id][signal_worker] << block
      __subscriptions[signal_id][subscription_id] = block
      subscribe_to_signal(signal_id)

      true
    end

    def emit(signal_id, message = signal_id)
      serialized_signal_id = Rage::Internal.stream_name_for(signal_id)
      Iodine.publish("signal:#{serialized_signal_id}", message) if Iodine.running?
      # TODO: redis adapter
      # TODO: filter sender out?

      true
    end

    def off(signal_id, subscription_id)
      if !__subscriptions.has_key?(signal_id) && !__subscriptions[signal_id].has_key?(subscription_id)
        raise ArgumentError, "subscription doesn't exist"
      end

      callback = __subscriptions[signal_id].delete(subscription_id)

      signal_worker = Fiber[:signal_worker]
      raise unless signal_worker # TODO: iterate through all workers instead?

      worker_callbacks = __signals[signal_id][signal_worker]
      worker_callbacks.delete(callback)
      __signals[signal_id].delete(signal_worker) if worker_callbacks.empty?

      true
    end

    private

    def build_signal_worker
      # new fiber inherits parent's fiber storage with `live_components`;
      # the fiber is cached per connection in case `on` is called for multiple components in a loop
      Fiber[:signal_worker] ||= Fiber.schedule do
        loop do
          callback, message = Fiber.yield
          callback.call(message)
        rescue => e
          Rage::Errors.report(e)
          Rage.logger.error("#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        end
      end
    end

    def subscribe_to_signal(signal_id)
      serialized_signal_id = Rage::Internal.stream_name_for(signal_id)
      return if Iodine.subscribed?("signal:#{serialized_signal_id}")

      Iodine.subscribe("signal:#{serialized_signal_id}") do |_, msg|
        __signals[signal_id].each do |worker, callbacks|
          callbacks.each { |callback| worker.resume([callback, msg]) }
        end
      end

      Iodine.on_state(:start_shutdown) do
        Iodine.unsubscribe("signal:#{serialized_signal_id}")
      end
    end
  end
end

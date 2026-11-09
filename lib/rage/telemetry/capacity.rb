# frozen_string_literal: true

module Rage::Telemetry
  ##
  # The `Rage::Telemetry::Capacity` module exposes framework-owned runtime
  # state - metrics describing the server's current load and resource utilization
  # that cannot be derived from existing spans.
  #
  # Unlike spans, capacity metrics aren't tied to a specific operation or
  # event, they reflect the server state at the moment they are read, and
  # are meant to be sampled periodically rather than triggered by handlers.
  #
  # Combine with {Rage::Telemetry.every} to report a metric on a fixed
  # interval:
  #
  #     Rage::Telemetry.every(1000) do
  #       MyMetrics.gauge("server.queued_connections", Rage::Telemetry::Capacity.queued_connections)
  #     end
  #
  # @see Rage::Telemetry.every
  #
  module Capacity
    # both counters from `Iodine::Perf.elu_snapshot` at the moment of the
    # previous {event_loop_utilization} call; the difference between reads
    # yields the utilization window ("since the previous call").
    @last_sample = nil
    # whether the ELU lifecycle hooks (iodine `:pre_start` / `:enter_child`
    # state callbacks) were registered; they are installed once, on the first
    # {enable_event_loop_utilization!} call.
    @elu_hooks_registered = false

    class << self
      # Returns the number of established connections currently waiting in the
      # kernel accept queue for the server listening sockets. This is the
      # count of clients that have already completed the TCP handshake but
      # haven't yet been picked up by the application via `accept()`.
      #
      # A value that stays bigger than 0 is a sign the server isn't accepting
      # connections fast enough to keep up with incoming traffic.
      #
      # @raise [NotImplementedError] on non-Linux systems
      # @return [Integer] the accept-queue depth
      def queued_connections
        accept_queue_depth = Iodine::Perf.queued_connections
        raise NotImplementedError if accept_queue_depth.nil?

        accept_queue_depth
      end

      # Opts into event-loop utilization tracking. Call it before the server
      # starts (e.g. in a config initializer) so forked workers begin with a
      # fresh measurement window.
      #
      # Calling it more than once does nothing. ELU tracking stays off until
      # this is called; {event_loop_utilization} returns `nil` while it's off.
      #
      # @return [true]
      def enable_event_loop_utilization!
        Iodine::Perf.elu_enable_idle_time!

        unless @elu_hooks_registered
          @elu_hooks_registered = true
          # start the sample window when the reactor starts, so the first
          # reading doesn't cover the boot interval before the server runs.
          Iodine.on_state(:pre_start) { @last_sample = Iodine::Perf.elu_snapshot }
          # forked workers restart the iodine counters, so the per-worker
          # sample point resets as soon as the child starts (the single
          # worker case never forks and keeps the :pre_start window).
          Iodine.on_state(:enter_child) { @last_sample = nil }
        end

        true
      end

      # Reports how busy the server's event loop has been since the previous
      # call: `0.0` means fully idle, `1.0` means fully busy.
      #
      # A gauge around 1.0 on a mostly idle server, or a value that stays
      # close to 1.0 across a burst, is a sign the event loop can't keep up
      # with the traffic.
      #
      # The very first call after tracking turns on only saves the starting
      # point and returns `0.0` - when tracking is enabled before the server
      # starts, the window opens at reactor startup and the first reported
      # value is already real data.
      #
      # Returns `nil` when tracking is off, or once after a window reset (a
      # clock anomaly) - the following call measures normally again.
      #
      # @return [Float, nil]
      def event_loop_utilization
        idle, elapsed = Iodine::Perf.elu_snapshot
        return nil if idle.nil?

        if @last_sample.nil?
          @last_sample = [idle, elapsed]
          return 0.0
        end

        diff_idle = idle - @last_sample[0]
        diff_elapsed = elapsed - @last_sample[1]
        @last_sample = [idle, elapsed]

        # The counters moved backwards (a forked worker restarts them): this
        # window can't be measured. The saved sample now points to the
        # current moment, so the next call starts clean.
        return nil if diff_idle < 0 || diff_elapsed <= 0

        1.0 - diff_idle.to_f / diff_elapsed
      end
    end
  end
end

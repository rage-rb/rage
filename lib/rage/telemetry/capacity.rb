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
    end
  end
end

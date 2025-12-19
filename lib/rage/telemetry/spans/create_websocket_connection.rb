# frozen_string_literal: true

##
# The **cable.websocket.handshake** span wraps the WebSocket connection handshake process.
#
# This span is started when a WebSocket connection is being established and is finished once the handshake is complete.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::CreateWebsocketConnection
  class << self
    # @private
    def id
      "cable.websocket.handshake"
    end

    # @private
    def span_parameters
      %w[env:]
    end

    # @private
    def handler_arguments
      {
        name: '"WebSocket.handshake"',
        env: "env"
      }
    end

    # @!parse [ruby]
    #   # @param id ["cable.websocket.handshake"] ID of the span
    #   # @param name ["WebSocket.handshake"] human-readable name of the operation
    #   # @param env [Hash] Rack environment hash that will be attached to the underlying WebSocket connection, allowing you to associate arbitrary data with the connection
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "cable.websocket.handshake", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, env:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, env:)
    #   end
  end
end

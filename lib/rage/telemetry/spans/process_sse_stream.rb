# frozen_string_literal: true

##
# The **sse.stream.process** span wraps the processing of an SSE stream.
#
# This span starts when a connection is opened and ends when the stream is finished.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessSSEStream
  class << self
    # @private
    def id
      "sse.stream.process"
    end

    # @private
    def span_parameters
      %w[connection: type:]
    end

    # @private
    def handler_arguments
      {
        name: '"SSE.process"',
        env: "connection.env",
        type: "type"
      }
    end

    # @!parse [ruby]
    #   # @param id ["sse.stream.process"] ID of the span
    #   # @param name ["SSE.process"] human-readable name of the operation
    #   # @param env [Hash] the Rack environment associated with the connection
    #   # @param type [:stream, :single, :manual] the type of the SSE stream
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "sse.stream.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, env:, type:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, env:, type:)
    #   end
  end
end

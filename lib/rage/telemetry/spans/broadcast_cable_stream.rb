# frozen_string_literal: true

##
# The **cable.stream.broadcast** span wraps the process of broadcasting a message to a `Rage::Cable` stream.
#
# This span is started when {Rage::Cable.broadcast Rage::Cable.broadcast} is called, and ends when the broadcast operation is complete.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::BroadcastCableStream
  class << self
    # @private
    def id
      "cable.stream.broadcast"
    end

    # @private
    def span_parameters
      %w[stream:]
    end

    # @private
    def handler_arguments
      {
        name: '"Rage::Cable.broadcast"',
        stream: "stream"
      }
    end

    # @!parse [ruby]
    #   # @param id ["cable.stream.broadcast"] ID of the span
    #   # @param name ["Rage::Cable.broadcast"] human-readable name of the operation
    #   # @param stream [String] the name of the stream to which the message is being broadcasted
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "cable.stream.broadcast", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, stream:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, stream:)
    #   end
  end
end

# frozen_string_literal: true

##
# The **cable.connection.process** span wraps the processing of a connection action in {Rage::Cable Rage::Cable}.
#
# This span is started just before the action method is invoked on the channel, and is ended immediately after the action method returns.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessCableConnection
  class << self
    # @private
    def id
      "cable.connection.process"
    end

    # @private
    def span_parameters
      %w[connection:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{connection.class}#connect"',
        connection: "connection"
      }
    end

    # @!parse [ruby]
    #   # @param id ["cable.connection.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `RageCable::Connection#receive`)
    #   # @param connection [Rage::Cable::Connection] the connection being processed
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "cable.connection.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, connection:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, connection:)
    #   end
  end
end

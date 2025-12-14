# frozen_string_literal: true

##
# The **cable.action.process** span wraps the processing of a single {Rage::Cable Rage::Cable} channel action.
#
# This span is started just before the action method is invoked on the channel, and is ended immediately after the action method returns.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessCableAction
  class << self
    # @private
    def id
      "cable.action.process"
    end

    # @private
    def span_parameters
      %w[channel: data: action_name:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{channel.class}##{action_name}"',
        channel: "channel",
        data: "data"
      }
    end

    # @!parse [ruby]
    #   # @param id ["cable.action.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `ChatChannel#receive`)
    #   # @param channel [Rage::Cable::Channel] the channel instance processing the action
    #   # @param data [Hash, nil] the data payload sent with the action
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "cable.action.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, channel:, data:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, channel:, data:)
    #   end
  end
end

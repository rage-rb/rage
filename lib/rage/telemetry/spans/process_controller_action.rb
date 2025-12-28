# frozen_string_literal: true

##
# The **controller.action.process** span wraps the processing of a controller action.
#
# This span is emitted for every controller action that is executed.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessControllerAction
  class << self
    # @private
    def id
      "controller.action.process"
    end

    # @private
    def span_parameters
      %w[controller: params:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{controller.class}##{params[:action]}"',
        controller: "controller",
        request: "controller.request",
        response: "controller.response",
        env: "controller.__env"
      }
    end

    # @!parse [ruby]
    #   # @param id ["controller.action.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `"UsersController#index"`)
    #   # @param controller [RageController::API] the controller instance being executed
    #   # @param request [Rage::Request] the request object associated with the action
    #   # @param response [Rage::Response] the response object associated with the action
    #   # @param env [Hash] the Rack environment
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "controller.action.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, controller:, request:, response:, env:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, controller:, request:, response:, env:)
    #   end
  end
end

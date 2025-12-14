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
        controller: "controller"
      }
    end

    # @!parse [ruby]
    #   # @param id ["controller.action.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `"UsersController#index"`)
    #   # @param controller [RageController::API] the controller instance being executed
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "controller.action.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, controller:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, controller:)
    #   end
  end
end

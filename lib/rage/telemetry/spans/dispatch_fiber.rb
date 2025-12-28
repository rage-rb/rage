# frozen_string_literal: true

##
# The **core.fiber.dispatch** span tracks the scheduling and processing of system-level fibers created by the framework to process requests and deferred tasks.
#
# This span is started when a system fiber begins processing and ends when the fiber has completed processing.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::DispatchFiber
  class << self
    # @private
    def id
      "core.fiber.dispatch"
    end

    # @private
    def span_parameters
      []
    end

    # @private
    def handler_arguments
      {
        name: '"Fiber.dispatch"'
      }
    end

    # @!parse [ruby]
    #   # @param id ["core.fiber.dispatch"] ID of the span
    #   # @param name ["Fiber.dispatch"] human-readable name of the operation
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "core.fiber.dispatch", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:)
    #   end
  end
end

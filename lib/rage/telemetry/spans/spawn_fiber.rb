# frozen_string_literal: true

##
# The **core.fiber.spawn** span tracks the scheduling and processing of application-level fibers created via {Fiber.schedule}.
#
# This span is started when a fiber begins processing and ends when the fiber has completed processing.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::SpawnFiber
  class << self
    # @private
    def id
      "core.fiber.spawn"
    end

    # @private
    def span_parameters
      %w[parent:]
    end

    # @private
    def handler_arguments
      {
        name: '"Fiber.schedule"',
        parent: "parent"
      }
    end

    # @!parse [ruby]
    #   # @param id ["core.fiber.spawn"] ID of the span
    #   # @param name ["Fiber.schedule"] human-readable name of the operation
    #   # @param parent [Fiber] the parent fiber that the current fiber was scheduled from
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "core.fiber.spawn", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, parent:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, parent:)
    #   end
  end
end

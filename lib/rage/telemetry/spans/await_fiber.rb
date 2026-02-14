# frozen_string_literal: true

##
# The **core.fiber.await** span wraps the processing of the {Fiber.await} call.
#
# This span is started when a fiber begins awaiting other fibers, and ends when all awaited fibers have completed.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::AwaitFiber
  class << self
    # @private
    def id
      "core.fiber.await"
    end

    # @private
    def span_parameters
      %w[fibers:]
    end

    # @private
    def handler_arguments
      {
        name: '"Fiber.await"',
        fibers: "Array(fibers)"
      }
    end

    # @!parse [ruby]
    #   # @param id ["core.fiber.await"] ID of the span
    #   # @param name ["Fiber.await"] human-readable name of the operation
    #   # @param fibers [Array<Fiber>] the fibers the current fiber is awaiting
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "core.fiber.await", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, fibers:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, fibers:)
    #   end
  end
end

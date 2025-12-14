# frozen_string_literal: true

##
# The **deferred.task.enqueue** span tracks the enqueuing of a deferred task.
#
# This span is triggered when a deferred task is enqueued.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::EnqueueDeferredTask
  class << self
    # @private
    def id
      "deferred.task.enqueue"
    end

    # @private
    def span_parameters
      %w[task_class:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{task_class}#enqueue"',
        task_class: "task_class"
      }
    end

    # @!parse [ruby]
    #   # @param id ["deferred.task.enqueue"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `SendConfirmationEmail#enqueue`)
    #   # @param task_class [Class] the deferred task being enqueued
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "deferred.task.enqueue", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, task_class:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, task_class:)
    #   end
  end
end

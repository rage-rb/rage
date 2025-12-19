# frozen_string_literal: true

##
# The **deferred.task.process** span tracks the processing of a deferred task.
#
# This span is started when a deferred task begins processing and ends when the task has completed processing.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessDeferredTask
  class << self
    # @private
    def id
      "deferred.task.process"
    end

    # @private
    def span_parameters
      %w[task: context:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{task.class}#perform"',
        task: "task",
        task_class: "task.class",
        task_context: "Rage::Deferred::Context.get_or_create_user_context(context)"
      }
    end

    # @!parse [ruby]
    #   # @param id ["deferred.task.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `SendConfirmationEmail#perform`)
    #   # @param task [Rage::Deferred::Task] the deferred task being processed
    #   # @param task_class [Class] the class of the deferred task being processed
    #   # @param task_context [Hash] the context is serialized together with the deferred task and allows passing data between telemetry handlers or deferred middleware without exposing it to the task itself
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "deferred.task.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, task:, task_class:, task_context:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, task:, task_class:, task_context:)
    #   end
  end
end

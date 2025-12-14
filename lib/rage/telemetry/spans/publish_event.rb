# frozen_string_literal: true

##
# The **events.event.publish** span tracks the publishing of an event.
#
# This span is triggered whenever an event is published via {Rage::Events.publish Rage::Events.publish}.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::PublishEvent
  class << self
    # @private
    def id
      "events.event.publish"
    end

    # @private
    def span_parameters
      %w[event: context:]
    end

    # @private
    def handler_arguments
      {
        name: '"Events.publish(#{event.class})"',
        event: "event",
        context: "context",
        subscriber_classes: "Rage::Events.__get_subscribers(event.class)"
      }
    end

    # @!parse [ruby]
    #   # @param id ["events.event.publish"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `Events.publish(UpdateRecommendations)`)
    #   # @param event [Object] the event being published
    #   # @param context [Object, nil] the additional context passed along with the event
    #   # @param subscriber_classes [Array<Class>] the list of subscriber classes that will receive the event
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "events.event.publish", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, event:, context:, subscriber_classes:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, event:, context:, subscriber_classes:)
    #   end
  end
end

# frozen_string_literal: true

##
# The **events.subscriber.process** span tracks the processing of an event by a subscriber.
#
# This span is started when an event begins processing by a subscriber and ends when the processing has completed.
# See {handle handle} for the list of arguments passed to handler methods.
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
#
class Rage::Telemetry::Spans::ProcessEventSubscriber
  class << self
    # @private
    def id
      "events.subscriber.process"
    end

    # @private
    def span_parameters
      %w[event: context: subscriber:]
    end

    # @private
    def handler_arguments
      {
        name: '"#{subscriber.class}#call"',
        subscriber: "subscriber",
        event: "event",
        context: "context"
      }
    end

    # @!parse [ruby]
    #   # @param id ["events.subscriber.process"] ID of the span
    #   # @param name [String] human-readable name of the operation (e.g., `UpdateRecommendations#call`)
    #   # @param subscriber [Rage::Events::Subscriber] the subscriber instance processing the event
    #   # @param event [Object] the event being processed
    #   # @param context [Object, nil] the additional context passed along with the event
    #   # @yieldreturn [Rage::Telemetry::SpanResult]
    #   #
    #   # @example
    #   #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #   #     handle "events.subscriber.process", with: :my_handler
    #   #
    #   #     def my_handler(id:, name:, subscriber:, event:, context:)
    #   #       yield
    #   #     end
    #   #   end
    #   # @note Rage automatically detects which parameters your handler method accepts and only passes those parameters.
    #   #   You can omit any of the parameters described here.
    #   def handle(id:, name:, subscriber:, event:, context:)
    #   end
  end
end

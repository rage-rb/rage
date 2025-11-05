# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::PublishEvent < Rage::Telemetry::Instrumentation
  class << self
    def id
      "events.event.publish"
    end

    def component_loaded?
      !Rage.autoload?(:Events)
    end

    def context_resolver
      id = self.id

      ->(event, context: nil) do
        {
          id:,
          name: "Events.publish(#{event.class})",
          payload: { event:, context:, subscribers: __get_subscribers(event.class) }
        }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)
      decorator.register(:publish)
      Rage::Events.singleton_class.prepend(decorator)
    end
  end
end

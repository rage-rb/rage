# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ProcessEventSubscriber < Rage::Telemetry::Instrumentation
  class << self
    def id
      "events.subscriber.process"
    end

    def component_loaded?
      !Rage.autoload?(:Events)
    end

    def context_resolver
      id = self.id

      ->(event, context: nil) do
        { id:, name: "#{self.class}#call", payload: { subscriber: self, event:, context: } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)
      decorator.register(:__call)
      Rage::Events::Subscriber.prepend(decorator)
    end
  end
end

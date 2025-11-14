# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ProcessCableAction < Rage::Telemetry::Instrumentation
  class << self
    def id
      "cable.action.process"
    end

    def component_loaded?
      !Rage.autoload?(:Deferred)
    end

    def context_resolver
      id = self.id

      ->(data = nil) do
        { id:, name: "#{self.class}##{action_name}", payload: { channel: self, data: } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)

      decorator.define_method(:__register_actions) do
        result = super()

        __prepared_actions.each_key { |action| decorator.register(action) }
        prepend(decorator)

        result
      end

      Rage::Cable::Channel.singleton_class.prepend(decorator)
    end
  end
end

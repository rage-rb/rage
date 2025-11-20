# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ProcessCableConnection < Rage::Telemetry::Instrumentation
  class << self
    def id
      "cable.connection.process"
    end

    def component_loaded?
      !Rage.autoload?(:Cable)
    end

    def context_resolver
      id = self.id

      ->() do
        { id:, name: "#{self.class}#connect", payload: { connection: self } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)

      decorator.define_method(:inherited) do |klass|
        super(klass)
        decorator.register(:connect)
        klass.prepend(decorator)
      end

      Rage::Cable::Connection.singleton_class.prepend(decorator)
    end
  end
end

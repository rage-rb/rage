# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ProcessDeferredTask < Rage::Telemetry::Instrumentation
  class << self
    def id
      "deferred.task.process"
    end

    def component_loaded?
      !Rage.autoload?(:Deferred)
    end

    def context_resolver
      id = self.id

      ->(_) do
        { id:, name: "#{self.class}#perform", payload: { task: self } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)
      decorator.register(:__perform)
      Rage::Deferred::Task.prepend(decorator)
    end
  end
end

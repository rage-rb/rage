# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::AwaitFiber < Rage::Telemetry::Instrumentation
  class << self
    def id
      "core.fiber.await"
    end

    def context_resolver
      id = self.id

      ->(fibers) do
        { id:, name: "Fiber.await", payload: { fibers: Array(fibers) } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)
      decorator.register(:await)
      Fiber.singleton_class.prepend(decorator)
    end
  end
end

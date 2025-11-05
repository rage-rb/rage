# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ScheduleFiber < Rage::Telemetry::Instrumentation
  class << self
    def id
      "core.fiber.schedule"
    end

    def context_resolver
      id = self.id

      ->() { { id:, name: "Fiber.schedule" } }
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver) do |_|
        instrumentation_block.call(_) if Fiber.current != Fiber.scheduler.root_fiber
      end
      decorator.register(:fiber)
      Rage::FiberScheduler.prepend(decorator)
    end
  end
end

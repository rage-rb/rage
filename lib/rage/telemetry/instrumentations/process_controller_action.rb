# frozen_string_literal: true

class Rage::Telemetry::Instrumentations::ProcessControllerAction < Rage::Telemetry::Instrumentation
  class << self
    def run_after_initialize?
      true
    end

    def id
      "controller.action.process"
    end

    def context_resolver
      id = self.id

      ->() do
        { id:, name: "#{self.class}##{params[:action]}", payload: { controller: self } }
      end
    end

    def apply(&instrumentation_block)
      decorator = Rage::Telemetry::Decorator.new(context_resolver, &instrumentation_block)

      descendants(RageController::API).each do |controller|
        actions = controller.instance_methods.select { |method_name| method_name.start_with?("__run_") }

        if actions.any?
          actions.each { |method_name| decorator.register(method_name) }
          controller.prepend(decorator)
        end
      end
    end
  end
end

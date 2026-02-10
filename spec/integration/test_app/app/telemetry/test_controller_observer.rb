class TestControllerObserver < Rage::Telemetry::Handler
  handle "controller.action.process", with: :monitor_controllers

  def self.monitor_controllers(name:)
    Rage.logger.tagged(name) do
      yield
    end
  end
end

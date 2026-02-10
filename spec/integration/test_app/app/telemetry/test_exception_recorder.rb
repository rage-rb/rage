class TestExceptionRecorder < Rage::Telemetry::Handler
  handle "controller.action.process", with: :record_exceptions

  def self.record_exceptions
    result = yield
    Rage.logger.error("telemetry recorded exception #{result.exception.message}") if result.error?
  end
end

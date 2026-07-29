# frozen_string_literal: true

require_relative "gc_pressure_checker"

module Rage::Telemetry::HealthChecks
  def self.__initialize
    return unless Rage.config.telemetry.gc_pressure_monitoring_enabled

    Iodine.run_every(1000) { GCPressureChecker.new.gc_stats }
  end
end

if Iodine.running?
  Rage::Telemetry::HealthChecks.__initialize
else
  Iodine.on_state(:on_start) { Rage::Telemetry::HealthChecks.__initialize }
end

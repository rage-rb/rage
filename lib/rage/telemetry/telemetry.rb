# frozen_string_literal: true

module Rage::Telemetry
  def self.instrument(instrumentation_id, &block)
    if instrumentation_id == "*" || instrumentation_id == :all
      __registry.each { |id, instrumentation| instrument(id, &block) if instrumentation.component_loaded? }
      return
    end

    instrumentation = __registry[instrumentation_id]

    unless instrumentation
      raise ArgumentError, "Unknown instrumentation ID '#{instrumentation_id}'"
    end

    if instrumentation.run_after_initialize?
      Rage.config.after_initialize { instrumentation.apply(&block) }
    else
      instrumentation.apply(&block)
    end
  end

  # @private
  def self.__registry
    @__registry ||= Instrumentation.subclasses.each_with_object({}) do |instrumentation, memo|
      memo[instrumentation.id] = instrumentation
    end
  end

  module Instrumentations
  end
end

require_relative "decorator"
require_relative "instrumentation"
Dir["#{__dir__}/instrumentations/*.rb"].each { |instrumentation| require_relative instrumentation }

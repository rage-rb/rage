class Rage::Telemetry::Instrumentation
  def self.run_after_initialize?
    false
  end

  def self.component_loaded?
    true
  end

  def self.descendants(klass)
    ObjectSpace.each_object(klass.singleton_class).select do |descendant|
      descendant != klass
    end
  end
end

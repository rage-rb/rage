class Rage::Telemetry::Instrumenter
  class << self
    attr_reader :handlers

    def instrument(*instrumentation_ids, except: nil, with:)
      all_instrumentation_ids = Rage::Telemetry.all_instrumentations

      if instrumentation_ids.one? && instrumentation_ids[0] == :all
        instrumentation_ids = all_instrumentation_ids
      end

      instrumentation_ids.each do |instrumentation_id|
        unless all_instrumentation_ids.include?(instrumentation_id)
          raise ArgumentError, "Unknown instrumentation ID '#{instrumentation_id}'"
        end
      end

      Array(except).each do |instrumentation_id_to_remove|
        unless all_instrumentation_ids.include?(instrumentation_id_to_remove)
          raise ArgumentError, "Unknown instrumentation ID '#{instrumentation_id_to_remove}'"
        end

        instrumentation_ids -= [instrumentation_id_to_remove]
      end

      @handlers ||= Hash.new { |hash, key| hash[key] = Set.new }
      instrumentation_ids.each do |instrumentation_id|
        @handlers[instrumentation_id] << with
      end
    end
  end
end

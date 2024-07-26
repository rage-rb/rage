# frozen_string_literal: true

require "set"

class Rage::Router::Constrainer
  attr_reader :strategies

  def initialize(custom_strategies)
    @strategies = {
      host: Rage::Router::Strategies::Host.new
    }

    @strategies_in_use = Set.new
  end

  def strategy_used?(strategy_name)
    @strategies_in_use.include?(strategy_name)
  end

  def has_constraint_strategy(strategy_name)
    custom_constraint_strategy = @strategies[strategy_name]
    if custom_constraint_strategy
      return custom_constraint_strategy.custom? || strategy_used?(strategy_name)
    end

    false
  end

  def derive_constraints(env)
  end

  # When new constraints start getting used, we need to rebuild the deriver to derive them. Do so if we see novel constraints used.
  def note_usage(constraints)
    if constraints
      before_size = @strategies_in_use.size

      constraints.each_key do |key|
        @strategies_in_use.add(key)
      end

      if before_size != @strategies_in_use.size
        __build_derive_constraints
      end
    end
  end

  def new_store_for_constraint(constraint)
    raise ArgumentError, "No strategy registered for constraint key '#{constraint}'" unless @strategies[constraint]
    @strategies[constraint].storage
  end

  def validate_constraints(constraints)
    constraints.each do |key, value|
      strategy = @strategies[key]
      raise ArgumentError, "No strategy registered for constraint key '#{key}'" unless strategy

      strategy.validate(value)
    end
  end

  # Optimization: build a fast function for deriving the constraints for all the strategies at once. We inline the definitions of the version constraint and the host constraint for performance.
  # If no constraining strategies are in use (no routes constrain on host, or version, or any custom strategies) then we don't need to derive constraints for each route match, so don't do anything special, and just return undefined
  # This allows us to not allocate an object to hold constraint values if no constraints are defined.
  def __build_derive_constraints
    return if @strategies_in_use.empty?

    lines = ["{"]

    @strategies_in_use.each do |key|
      strategy = @strategies[key]
      # Optimization: inline the derivation for the common built in constraints
      if !strategy.custom?
        if key == :host
          lines << "   host: env['HTTP_HOST'.freeze],"
        else
          raise ArgumentError, "unknown non-custom strategy for compiling constraint derivation function"
        end
      else
        lines << "  #{strategy.name}: @strategies[#{key}].derive_constraint(env),"
      end
    end

    lines << "}"

    instance_eval <<-RUBY
      def derive_constraints(env)
        #{lines.join("\n")}
      end
    RUBY
  end
end

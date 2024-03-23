# frozen_string_literal: true

class Rage::Router::HandlerStorage
  def initialize
    @unconstrained_handler = nil # optimized reference to the handler that will match most of the time
    @constraints = []
    @handlers = [] # unoptimized list of handler objects for which the fast matcher function will be compiled
    @constrained_handler_stores = nil
  end

  # This is the hot path for node handler finding -- change with care!
  def get_matching_handler(derived_constraints)
    return @unconstrained_handler unless derived_constraints
    get_handler_matching_constraints(derived_constraints)
  end

  def add_handler(constrainer, route)
    params = route[:params]
    constraints = route[:constraints]

    handler_object = {
      params: params,
      constraints: constraints,
      handler: route[:handler],
      create_params_object: compile_create_params_object(params, route[:defaults], route[:meta])
    }

    constraints_keys = constraints.keys
    if constraints_keys.empty?
      @unconstrained_handler = handler_object
    end

    constraints_keys.each do |constraint_key|
      @constraints << constraint_key unless @constraints.include?(constraint_key)
    end

    if @handlers.length >= 32
      raise "Limit reached: a maximum of 32 route handlers per node allowed when there are constraints"
    end

    @handlers << handler_object
    # Sort the most constrained handlers to the front of the list of handlers so they are tested first.
    @handlers.sort_by! { |a| a[:constraints].length }

    compile_get_handler_matching_constraints(constrainer)
  end

  private

  def compile_create_params_object(param_keys, defaults, meta)
    lines = if meta[:controller]
      [":controller => '#{meta[:controller]}'.freeze", ":action => '#{meta[:action]}'.freeze"]
    else
      []
    end

    param_keys.each_with_index do |key, i|
      lines << ":#{key} => param_values[#{i}]"
    end

    if defaults
      defaults.except(*param_keys.map(&:to_sym)).each do |key, value|
        lines << ":#{key} => '#{value}'.freeze"
      end
    end

    eval "->(param_values) { { #{lines.join(',')} } }"
  end

  def get_handler_matching_constraints(_derived_constraints)
  end

  # Builds a store object that maps from constraint values to a bitmap of handler indexes which pass the constraint for a value
  # So for a host constraint, this might look like { "fastify.io": 0b0010, "google.ca": 0b0101 }, meaning the 3rd handler is constrainted to fastify.io, and the 2nd and 4th handlers are constrained to google.ca.
  # The store's implementation comes from the strategies provided to the Router.
  def build_constraint_store(store, constraint)
    @handlers.each_with_index do |handler, i|
      constraint_value = handler[:constraints][constraint]
      if constraint_value
        indexes = store.get(constraint_value) || 0
        indexes |= 1 << i # set the i-th bit for the mask because this handler is constrained by this value https://stackoverflow.com/questions/1436438/how-do-you-set-clear-and-toggle-a-single-bit-in-javascrip
        store.set(constraint_value, indexes)
      end
    end
  end

  # Builds a bitmask for a given constraint that has a bit for each handler index that is 0 when that handler *is* constrained and 1 when the handler *isnt* constrainted. This is opposite to what might be obvious, but is just for convienience when doing the bitwise operations.
  def constrained_index_bitmask(constraint)
    mask = 0

    @handlers.each_with_index do |handler, i|
      constraint_value = handler[:constraints][constraint]
      mask |= 1 << i if constraint_value
    end

    ~mask
  end

  # Compile a fast function to match the handlers for this node
  # The function implements a general case multi-constraint matching algorithm.
  # The general idea is this: we have a bunch of handlers, each with a potentially different set of constraints, and sometimes none at all. We're given a list of constraint values and we have to use the constraint-value-comparison strategies to see which handlers match the constraint values passed in.
  # We do this by asking each constraint store which handler indexes match the given constraint value for each store. Trickily, the handlers that a store says match are the handlers constrained by that store, but handlers that aren't constrained at all by that store could still match just fine. So, each constraint store can only describe matches for it, and it won't have any bearing on the handlers it doesn't care about. For this reason, we have to ask each stores which handlers match and track which have been matched (or not cared about) by all of them.
  # We use bitmaps to represent these lists of matches so we can use bitwise operations to implement this efficiently. Bitmaps are cheap to allocate, let us implement this masking behaviour in one CPU instruction, and are quite compact in memory. We start with a bitmap set to all 1s representing every handler that is a match candidate, and then for each constraint, see which handlers match using the store, and then mask the result by the mask of handlers that that store applies to, and bitwise AND with the candidate list. Phew.
  # We consider all this compiling function complexity to be worth it, because the naive implementation that just loops over the handlers asking which stores match is quite a bit slower.
  def compile_get_handler_matching_constraints(constrainer)
    @constrained_handler_stores = {}

    @constraints.each do |constraint|
      store = constrainer.new_store_for_constraint(constraint)
      @constrained_handler_stores[constraint] = store

      build_constraint_store(store, constraint)
    end

    lines = []
    lines << <<-RUBY
      candidates = #{(1 << @handlers.length) - 1}
      mask, matches = nil
    RUBY

    @constraints.each do |constraint|
      # Setup the mask for indexes this constraint applies to. The mask bits are set to 1 for each position if the constraint applies.
      lines << <<-RUBY
        mask = #{constrained_index_bitmask(constraint)}
        value = derived_constraints[:#{constraint}]
      RUBY

      # If there's no constraint value, none of the handlers constrained by this constraint can match. Remove them from the candidates.
      # If there is a constraint value, get the matching indexes bitmap from the store, and mask it down to only the indexes this constraint applies to, and then bitwise and with the candidates list to leave only matching candidates left.
      strategy = constrainer.strategies[constraint]
      match_mask = strategy.must_match_when_derived ? "matches" : "(matches | mask)"

      lines.push << <<-RUBY
        if !value
          candidates &= mask
        else
          matches = @constrained_handler_stores[:#{constraint}].get(value) || 0
          candidates &= #{match_mask}
        end

        return nil if candidates == 0
      RUBY
    end

    # There are some constraints that can be derived and marked as "must match", where if they are derived, they only match routes that actually have a constraint on the value, like the SemVer version constraint.
    # An example: a request comes in for version 1.x, and this node has a handler that matches the path, but there's no version constraint. For SemVer, the find-my-way semantics do not match this handler to that request.
    # This function is used by Nodes with handlers to match when they don't have any constrained routes to exclude request that do have must match derived constraints present.
    constrainer.strategies.each do |constraint, strategy|
      if strategy.must_match_when_derived && !@constraints.include?(constraint)
        lines << "return nil if derived_constraints[:#{constraint}]"
      end
    end

    # Return the first handler whose bit is set in the candidates https://stackoverflow.com/questions/18134985/how-to-find-index-of-first-set-bit
    lines << "return @handlers[Math.log2(candidates).floor]"

    instance_eval <<-RUBY
      def get_handler_matching_constraints(derived_constraints)
        #{lines.join("\n")}
      end
    RUBY
  end
end

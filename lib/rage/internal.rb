# frozen_string_literal: true

# @private
class Rage::Internal
  class << self
    # Define a method based on a block.
    # @param klass [Class] the class to define the method in
    # @param block [Proc] the implementation of the new method
    # @return [Symbol] the name of the newly defined method
    def define_dynamic_method(klass, block)
      name = dynamic_name_seed.next.join
      klass.define_method("__rage_dynamic_#{name}", block)
    end

    # Define a method that will call a specified method if a condition is `true` or yield if `false`.
    # @param klass [Class] the class to define the method in
    # @param method_name [Symbol] the method to call if the condition is `true`
    # @return [Symbol] the name of the newly defined method
    def define_maybe_yield(klass, method_name)
      name = dynamic_name_seed.next.join

      klass.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __rage_dynamic_#{name}(condition)
          if condition
            #{method_name} { yield }
          else
            yield
          end
        end
      RUBY
    end

    # Build a string representation of keyword arguments based on the parameters expected by the method.
    # @param method [Method, Proc] the method to build arguments for
    # @param arguments [Hash] the arguments to include in the string representation
    # @return [String] the string representation of the method arguments
    def build_arguments(method, arguments)
      expected_parameters = method.parameters

      arguments.filter_map { |arg_name, arg_value|
        if expected_parameters.any? { |param_type, param_name| param_name == arg_name || param_type == :keyrest }
          "#{arg_name}: #{arg_value}"
        end
      }.join(", ")
    end

    private

    def dynamic_name_seed
      @dynamic_name_seed ||= ("a".."j").to_a.permutation
    end
  end
end

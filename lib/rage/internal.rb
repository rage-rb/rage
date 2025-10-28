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

    private

    def dynamic_name_seed
      @dynamic_name_seed ||= ("a".."j").to_a.permutation
    end
  end
end

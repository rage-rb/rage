class Rage::Telemetry::Decorator < Module
  def initialize(context_resolver, &block)
    @decorator_method = Rage::Internal.define_dynamic_method(self, block)
    @context_resolver = Rage::Internal.define_dynamic_method(self, context_resolver)
  end

  def register(decorated_method_name)
    return if method_defined?(decorated_method_name)

    decorator_arity = instance_method(@decorator_method).arity
    decorator_arguments = if decorator_arity == 0
      :none
    elsif decorator_arity == 1
      :decorated
    else
      :decorated_with_context
    end

    module_eval <<~RUBY, __FILE__, __LINE__ + 1
      def #{decorated_method_name}(...)
        super_called = false
        super_result, super_error = nil

        #{if decorator_arguments == :decorated_with_context
          <<~RUBY
            context = #{@context_resolver}(...)
          RUBY
        end}

        decorated = -> do
          super_called = true
          super_result = super(...)
          nil
        rescue Exception => e
          super_error = e
          #{if decorator_arguments == :decorated_with_context
            <<~RUBY
              context[:exception] = [e.class.name, e.message]
              context[:exception_object] = e
            RUBY
          end}
          nil
        end

        #{if decorator_arguments == :none
          <<~RUBY
            #{@decorator_method}
          RUBY
        elsif decorator_arguments == :decorated
          <<~RUBY
            #{@decorator_method}(decorated)
          RUBY
        else
          <<~RUBY
            #{@decorator_method}(decorated, context)
          RUBY
        end}

      rescue Exception => e
        Rage.logger.error("Unhandled exception in Rage::Telemetry instrumenter: \#{e.class} (\#{e.message}):\n\#{e.backtrace.join("\n")}")

      ensure
        decorated.call unless super_called
        super_error ? raise(super_error) : return(super_result)
      end
    RUBY
  end
end

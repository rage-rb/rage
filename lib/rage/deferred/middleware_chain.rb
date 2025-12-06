# frozen_string_literal: true

class Rage::Deferred::MiddlewareChain
  def initialize(enqueue_middleware:, perform_middleware:)
    @enqueue_middleware = enqueue_middleware
    @perform_middleware = perform_middleware

    build_enqueue_chain!
    build_perform_chain!
  end

  private

  def build_enqueue_chain!
    raw_arguments = {
      phase: ":enqueue",
      args: "Rage::Deferred::Context.get_or_create_args(context)",
      kwargs: "Rage::Deferred::Context.get_or_create_kwargs(context)",
      context: "Rage::Deferred::Context.get_or_create_user_context(context)",
      task_class: "Rage::Deferred::Context.get_task(context)",
      delay: "delay",
      delay_until: "delay_until"
    }

    self.class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def with_enqueue_middleware(context, delay:, delay_until:)
        #{build_middleware_chain(:@enqueue_middleware, raw_arguments)}
      end
    RUBY
  end

  def build_perform_chain!
    raw_arguments = {
      phase: ":perform",
      args: "Rage::Deferred::Context.get_or_create_args(context)",
      kwargs: "Rage::Deferred::Context.get_or_create_kwargs(context)",
      context: "Rage::Deferred::Context.get_or_create_user_context(context)",
      task_class: "task.class",
      task: "task"
    }

    self.class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def with_perform_middleware(context, task:)
        #{build_middleware_chain(:@perform_middleware, raw_arguments)}
      end
    RUBY
  end

  def build_middleware_chain(middlewares_var, raw_arguments)
    middlewares = instance_variable_get(middlewares_var)
    i = middlewares.length

    middlewares.reverse.inject("yield") do |memo, middleware_with_args|
      middleware, _, _ = middleware_with_args
      arguments = Rage::Internal.build_arguments(middleware.instance_method(:call), raw_arguments)
      i -= 1

      <<~RUBY
        middleware, args, block = #{middlewares_var}[#{i}]

        middleware.new(*args, &block).call(#{arguments}) do
          #{memo}
        end
      RUBY
    end
  end
end

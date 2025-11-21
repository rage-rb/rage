# frozen_string_literal: true

class Rage::LogProcessor
  DEFAULT_LOG_CONTEXT = {}.freeze
  private_constant :DEFAULT_LOG_CONTEXT

  attr_reader :custom_context, :custom_tags

  def initialize
    rebuild!
  end

  def add_custom_context(context_objects)
    @custom_context = context_objects
    rebuild!
  end

  def add_custom_tags(tag_objects)
    @custom_tags = tag_objects
    rebuild!
  end

  def finalize_request_logger(env, response, params)
    logger = Thread.current[:rage_logger]

    duration = (
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - logger[:request_start]) * 1000
    ).round(2)

    logger[:final] = { env:, params:, response:, duration: }
    Rage.logger.info("")
    logger[:final] = nil
  end

  private

  def build_custom_context_proc
    calls = @custom_context.map.with_index do |context_object, i|
      if context_object.is_a?(Hash)
        "@custom_context[#{i}]"
      else
        context_object.arity == 0 ?
          "@custom_context[#{i}].call || DEFAULT_LOG_CONTEXT" :
          "@custom_context[#{i}].call(env) || DEFAULT_LOG_CONTEXT"
      end
    end

    build_context_call = if calls.one?
      calls[0]
    else
      <<~RUBY
        {}.merge!(#{calls.join(", ")})
      RUBY
    end

    eval <<~RUBY
      ->(env) do
        #{build_context_call}
      rescue Exception => e
        Rage.logger.tagged(env["rage.request_id"]) do
          Rage.logger.error("Unhandled exception when building log context: \#{e.class} (\#{e.message}):\\n\#{e.backtrace.join("\\n")}")
        end
        DEFAULT_LOG_CONTEXT
      end
    RUBY
  end

  def build_custom_tags_proc
    calls = @custom_tags.map.with_index do |tag_object, i|
      if tag_object.is_a?(String)
        "@custom_tags[#{i}]"
      elsif tag_object.respond_to?(:to_str)
        "@custom_tags[#{i}].to_str"
      else
        tag_object.arity == 0 ? "*@custom_tags[#{i}].call" : "*@custom_tags[#{i}].call(env)"
      end
    end

    eval <<~RUBY
      ->(env) do
        [env["rage.request_id"], #{calls.join(", ")}]
      rescue Exception => e
        Rage.logger.tagged(env["rage.request_id"]) do
          Rage.logger.error("Unhandled exception when building log tags: \#{e.class} (\#{e.message}):\\n\#{e.backtrace.join("\\n")}")
        end
        [env["rage.request_id"]]
      end
    RUBY
  end

  def rebuild!
    context_call = if @custom_context&.any?
      @custom_log_context_proc = build_custom_context_proc
      "@custom_log_context_proc.call(env)"
    else
      "DEFAULT_LOG_CONTEXT"
    end

    tags_call = if @custom_tags&.any?
      @custom_log_tags_proc = build_custom_tags_proc
      "@custom_log_tags_proc.call(env)"
    else
      "[env[\"rage.request_id\"]]"
    end

    singleton_class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def init_request_logger(env)
        env["rage.request_id"] ||= Iodine::Rack::Utils.gen_request_tag

        Thread.current[:rage_logger] = {
          tags: #{tags_call},
          context: #{context_call},
          request_start: Process.clock_gettime(Process::CLOCK_MONOTONIC)
        }
      end
    RUBY
  end
end

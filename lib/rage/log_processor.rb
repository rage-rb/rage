# frozen_string_literal: true

class Rage::LogProcessor
  DEFAULT_LOG_CONTEXT = {}.freeze
  private_constant :DEFAULT_LOG_CONTEXT

  attr_reader :dynamic_tags, :dynamic_context

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
    duration = (
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - Fiber[:__rage_logger_request_start]) * 1000
    ).round(2)

    Fiber[:__rage_logger_final] = { env:, params:, response:, duration: }
    Rage.logger.info(nil)
    Fiber[:__rage_logger_final] = nil
  end

  private

  def build_static_tags
    calls = @custom_tags&.filter_map&.with_index do |tag_object, i|
      if tag_object.is_a?(String)
        "@custom_tags[#{i}]"
      elsif tag_object.respond_to?(:to_str)
        "@custom_tags[#{i}].to_str"
      end
    end

    unless calls&.any?
      return "[env[\"rage.request_id\"]]"
    end

    "[env[\"rage.request_id\"], #{calls.join(", ")}]"
  end

  def build_static_context
    calls = @custom_context&.filter_map&.with_index do |context_object, i|
      "@custom_context[#{i}]" if context_object.is_a?(Hash)
    end

    unless calls&.any?
      return "DEFAULT_LOG_CONTEXT"
    end

    if calls.one?
      calls[0]
    else
      "{}.merge!(#{calls.join(", ")})"
    end
  end

  def build_dynamic_tags_proc
    calls = @custom_tags&.filter_map&.with_index do |tag_object, i|
      if tag_object.respond_to?(:call)
        "*@custom_tags[#{i}].call"
      end
    end

    return unless calls&.any?

    eval <<~RUBY
      ->() do
        [#{calls.join(", ")}]
      end
    RUBY
  end

  def build_dynamic_context_proc
    calls = @custom_context&.filter_map&.with_index do |context_object, i|
      if context_object.respond_to?(:call)
        "@custom_context[#{i}].call || DEFAULT_LOG_CONTEXT"
      end
    end

    return unless calls&.any?

    eval <<~RUBY
      ->() do
        {}.merge!(#{calls.join(", ")})
      end
    RUBY
  end

  def rebuild!
    @dynamic_tags = build_dynamic_tags_proc
    @dynamic_context = build_dynamic_context_proc

    self.class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def init_request_logger(env)
        env["rage.request_id"] ||= Iodine::Rack::Utils.gen_request_tag

        Fiber[:__rage_logger_tags] = #{build_static_tags}
        Fiber[:__rage_logger_context] = #{build_static_context}
        Fiber[:__rage_logger_request_start] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    RUBY
  end
end

# frozen_string_literal: true

class Rage::Telemetry::Tracer
  DEFAULT_SPAN_RESULT = Rage::Telemetry::SpanResult.new.freeze
  private_constant :DEFAULT_SPAN_RESULT

  # @param spans_registry [Hash{String => Rage::Telemetry::Spans}]
  # @param handlers_map [Hash{String => Array<Rage::Telemetry::HandlerRef>}]
  def initialize(spans_registry, handlers_map)
    @spans_registry = spans_registry
    @handlers_map = handlers_map

    @all_handler_refs = handlers_map.values.flatten

    @spans_registry.each do |_, span|
      setup_noop(span)
    end
  end

  def setup
    @handlers_map.each do |span_id, handler_refs|
      setup_tracer(@spans_registry[span_id], handler_refs)
    end
  end

  private

  # @param span [Rage::Telemetry::Spans]
  def setup_noop(span)
    parameters = span.span_parameters.join(", ")

    self.class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def #{tracer_name(span.id)}(#{parameters})
        yield
      end
    RUBY
  end

  # @param span [Rage::Telemetry::Spans]
  # @param handler_refs [Array<Rage::Telemetry::HandlerRef>]
  def setup_tracer(span, handler_refs)
    yield_call = <<~RUBY
        yield_called = true
        yield_result = yield
        span_result = DEFAULT_SPAN_RESULT
      rescue => e
        yield_error = e
        span_result = Rage::Telemetry::SpanResult.new(e).freeze
    RUBY

    calls_chain = handler_refs.reverse.inject(yield_call) do |memo, handler_ref|
      handler_index = @all_handler_refs.index(handler_ref)

      handler_method = handler_ref.instance.method(handler_ref.method_name)
      handler_arguments = Rage::Internal.build_arguments(
        handler_method,
        { **span.handler_arguments, id: "#{span}.id" }
      )

      <<~RUBY
        @all_handler_refs[#{handler_index}].instance.#{handler_ref.method_name}(#{handler_arguments}) do
          #{memo}
          span_result
        end
      RUBY
    end

    parameters = span.span_parameters.join(", ")

    self.class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def #{tracer_name(span.id)}(#{parameters})
        span_result = yield_called = yield_result = yield_error = nil

        begin
          #{calls_chain}
        rescue Exception => e
          Rage.logger.error("Telemetry handler failed with error \#{e}:\\n\#{e.backtrace.join("\\n")}")
        end

        unless yield_called
          Rage.logger.warn("Telemetry handler didn't call `yield` when processing span '#{span.id}'\\n\#{caller.join("\\n")}")
          yield_result = yield
        end

        if yield_error
          raise yield_error
        else
          yield_result
        end
      end
    RUBY
  end

  def tracer_name(span_id)
    "span_#{span_id.gsub(".", "_")}"
  end
end

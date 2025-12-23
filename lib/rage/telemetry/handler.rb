# frozen_string_literal: true

##
# The class allows developers to define telemetry handlers that observe and react to specific span executions.
#
# Handlers are defined by subclassing `Rage::Telemetry::Handler` and using the `handle` class method
# to specify which spans to observe and which methods to invoke when those spans are executed.
#
# See {Rage::Telemetry::Spans} for a list of available spans and arguments passed to the handler methods.
#
# Each handler method is expected to call `yield` to pass control to the next handler in the stack or the framework's core logic.
# The call to `yield` returns an instance of {Rage::Telemetry::SpanResult} which contains information about the span execution.
#
# @example
#   class MyTelemetryHandler < Rage::Telemetry::Handler
#     handle "controller.action.process", with: :create_span
#
#     def create_span(name:)
#       MyObservabilitySDK.in_span(name) do
#         yield
#       end
#     end
#   end
#
class Rage::Telemetry::Handler
  class << self
    # @private
    attr_accessor :handlers_map

    # Defines which spans the handler will observe and which method to invoke for those spans.
    #
    # @param span_ids [Array<String>] one or more span IDs to observe; supports wildcards (`*`) to match multiple spans
    # @param with [Symbol] the method name to invoke when the specified spans are executed
    # @param except [String, Array<String>, nil] optional list of span IDs to exclude from observation; supports wildcards (`*`) to match multiple spans
    # @raise [ArgumentError] if any specified span ID is unknown or if no spans match a wildcard ID
    #
    # @example Observe a specific span
    #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #     handle "controller.action.process", with: :my_handler_method
    #
    #     def my_handler_method
    #       # ...
    #     end
    #   end
    #
    # @example Observe multiple spans with wildcards
    #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #     handle "cable.*", with: :my_handler_method
    #
    #     def my_handler_method
    #       # ...
    #     end
    #   end
    #
    # @example Observe all spans except specific ones
    #   class MyTelemetryHandler < Rage::Telemetry::Handler
    #     handle "*", except: "core.fiber.dispatch", with: :my_handler_method
    #
    #     def my_handler_method
    #       # ...
    #     end
    #   end
    #
    def handle(*span_ids, with:, except: nil)
      resolved_span_ids = resolve_span_ids(span_ids)

      if except
        resolved_span_ids -= resolve_span_ids(Array(except))
      end

      if @handlers_map.nil?
        @handlers_map = {}
      elsif @handlers_map.frozen?
        @handlers_map = @handlers_map.transform_values(&:dup)
      end

      resolved_span_ids.each do |span_id|
        @handlers_map[span_id] ||= Set.new
        @handlers_map[span_id] << with
      end
    end

    # @private
    def inherited(klass)
      klass.handlers_map = @handlers_map.freeze
    end

    private

    def resolve_span_ids(span_ids)
      all_span_ids = Rage::Telemetry.__registry.keys
      return all_span_ids if span_ids.include?("*")

      exact_span_ids, wildcard_span_ids = [], []

      # separate span IDs based on whether they contain wildcards
      span_ids.each do |span_id|
        if span_id.include?("*")
          wildcard_span_ids << span_id
        else
          exact_span_ids << span_id
        end
      end

      # validate exact span IDs
      resolved_span_ids = []

      exact_span_ids.each do |span_id|
        unless all_span_ids.include?(span_id)
          raise ArgumentError, "Unknown span ID '#{span_id}'"
        end

        resolved_span_ids << span_id
      end

      # validate and resolve wildcard span IDs
      wildcard_span_ids.each do |span_id|
        matcher = Regexp.new(span_id.gsub("*", "\\w+").gsub(".", "\\."))
        matched_span_ids = all_span_ids.select { |id| id.match?(matcher) }

        unless matched_span_ids.any?
          raise ArgumentError, "No spans match the wildcard ID '#{span_id}'"
        end

        resolved_span_ids += matched_span_ids
      end

      resolved_span_ids
    end
  end
end

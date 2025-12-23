# frozen_string_literal: true

##
# The `Rage::Telemetry` component provides an interface to monitor various operations and events within the Rage framework.
#
# To start using telemetry, define and register custom handlers that will process the telemetry data.
#
# 1. **Define Handlers**: Create custom telemetry handlers by subclassing {Rage::Telemetry::Handler Rage::Telemetry::Handler} and implementing the desired logic for processing telemetry data.
#
#     ```ruby
#     class MyTelemetryHandler < Rage::Telemetry::Handler
#       handle "controller.action.process", with: :log_action
#
#       def log_action(controller:)
#         puts "Processing action: #{controller.action_name}"
#         yield
#       end
#     end
#     ```
#
# 2. **Register Handlers**: Register your custom handlers in the Rage configuration.
#
#     ```ruby
#     Rage.configure do
#       config.telemetry.use MyTelemetryHandler.new
#     end
#     ```
#
# @see Rage::Telemetry::Handler Rage::Telemetry::Handler
# @see Rage::Telemetry::Spans Rage::Telemetry::Spans
#
module Rage::Telemetry
  # @private
  def self.__registry
    @__registry ||= Spans.constants.each_with_object({}) do |const, memo|
      span = Spans.const_get(const)
      memo[span.id] = span
    end
  end

  # @private
  def self.tracer
    @tracer ||= Tracer.new(__registry, Rage.config.telemetry.handlers_map)
  end

  # @private
  def self.__setup
    tracer.setup
  end

  ##
  # The namespace contains all telemetry span definitions.
  # Each span represents a specific operation or event within the framework that can be monitored and traced.
  #
  # Spans always pass two standard keyword arguments to their handlers:
  #
  # * `:id` - The unique identifier of the span.
  # * `:name` - The human-readable name of the operation.
  #
  # Handlers can also receive additional context-specific keyword arguments as defined by each span.
  #
  # # Available Spans
  #
  # | ID | Reference | Description |
  # | --- | --- |
  # | `core.fiber.dispatch` | {DispatchFiber} | Wraps the scheduling and processing of system-level fibers created by the framework to process requests and deferred tasks |
  # | `core.fiber.spawn` | {SpawnFiber} | Wraps the scheduling and processing of application-level fibers created via {Fiber.schedule} |
  # | `core.fiber.await` | {AwaitFiber} | Wraps the processing of the {Fiber.await} calls |
  # | `controller.action.process` | {ProcessControllerAction} | Wraps the processing of controller actions |
  # | `cable.websocket.handshake` | {CreateWebsocketConnection} | Wraps the WebSocket connection handshake process |
  # | `cable.connection.process` | {ProcessCableConnection} | Wraps the processing of connect actions in {Rage::Cable Rage::Cable} |
  # | `cable.action.process` | {ProcessCableAction} | Wraps the processing of {Rage::Cable Rage::Cable} channel actions |
  # | `cable.stream.broadcast` | {BroadcastCableStream} | Wraps the broadcasting of messages to {Rage::Cable Rage::Cable} streams |
  # | `deferred.task.enqueue` | {EnqueueDeferredTask} | Wraps the enqueuing of deferred tasks |
  # | `deferred.task.process` | {ProcessDeferredTask} | Wraps the processing of deferred tasks |
  # | `events.event.publish` | {PublishEvent} | Wraps the publishing of events via {Rage::Events Rage::Events} |
  # | `events.subscriber.process` | {ProcessEventSubscriber} | Wraps the processing of events by subscribers |
  #
  module Spans
  end

  # @private
  HandlerRef = Data.define(:instance, :method_name)

  # Contains the result of a span execution.
  # @!attribute [r] exception
  #   @return [Exception, nil] The exception raised during the span execution, if any.
  # @example
  #   class MyTelemetryHandler < Rage::Telemetry::Handler
  #     handle "controller.action.process", with: :monitor_500
  #
  #     def monitor_500
  #       result = yield
  #
  #       if result.error?
  #         MyObservabilitySDK.notify("500 Error Detected", result.exception)
  #       end
  #     end
  #   end
  SpanResult = Struct.new(:exception) do
    # Returns `true` if the span resulted in an error.
    def error?
      !!exception
    end

    # Returns `true` if the span executed successfully.
    def success?
      !error?
    end
  end
end

require_relative "tracer"
require_relative "handler"
Dir["#{__dir__}/spans/*.rb"].each { |span| require_relative span }

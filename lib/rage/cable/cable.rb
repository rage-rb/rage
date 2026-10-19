# frozen_string_literal: true

##
# `Rage::Cable` provides built-in WebSocket support for Rage apps, similar to Action Cable in Rails. It lets you mount a separate WebSocket application, define channels and connections, subscribe clients to named streams, and broadcast messages in real time.
#
# Define a channel:
# ```ruby
# class ChatChannel < Rage::Cable::Channel
#   def subscribed
#     stream_from "chat"
#   end
#
#   def receive(data)
#     puts "Received message: #{data['message']}"
#   end
# end
# ```
#
# Mount the Cable application:
# ```ruby
# Rage.routes.draw do
#   mount Rage::Cable.application, at: "/cable"
# end
# ```
#
# Broadcast a message to a stream:
# ```ruby
# Rage.cable.broadcast("chat", { message: "Hello, world!" })
# ```
#
module Rage::Cable
  PUBSUB_BROADCASTER_ID = "cable"
  private_constant :PUBSUB_BROADCASTER_ID

  # Create a new Cable application.
  #
  # @example
  #   map "/cable" do
  #     run Rage.cable.application
  #   end
  def self.application(namespace: Object, protocol: nil)
    unless namespace.is_a?(Module)
      raise ArgumentError, "The `namespace` option must be a Module, got #{namespace.class}."
    end

    protocol = __protocol_for(protocol || Rage.config.cable.protocol)

    unless __protocols.include?(protocol)
      __protocols << protocol.tap(&:init)
      @__adapter&.add_broadcaster(PUBSUB_BROADCASTER_ID, Relay)
    end

    router = Router.new(protocol, namespace)
    handler = __build_handler(protocol, router)
    accept_response = [101, protocol.protocol_definition, []]

    application = ->(env) do
      Rage::Telemetry.tracer.span_cable_websocket_handshake(env:) do
        if env["HTTP_UPGRADE"] == "websocket" || env["HTTP_UPGRADE"]&.downcase == "websocket"
          env["rack.upgrade?"] = :websocket
          env["rack.upgrade"] = handler
          accept_response
        else
          [426, { "connection" => "upgrade", "upgrade" => "websocket" }, []]
        end
      end
    end

    chain = Rage.with_middlewares(application, Rage.config.cable.middlewares)

    chain.define_singleton_method(:__rage_root_app) do
      root_app = Rage.with_middlewares(application, Rage.config.cable.middlewares(include_http_middleware: false))
      root_app.define_singleton_method(:__rage_app_name) do
        namespace == Object ? "Rage::Cable" : "Rage::Cable(namespace: #{namespace})"
      end

      root_app
    end

    chain
  end

  # @private
  def self.__initialize
    if (adapter = Rage.config.pubsub.adapter)
      adapter.add_broadcaster(PUBSUB_BROADCASTER_ID, Relay)
      @__adapter = adapter
    end
  end

  # @private
  def self.__protocols
    @__protocols ||= []
  end

  # @private
  # @param protocol [:actioncable_v1_json, :raw_websocket_json, Class]
  def self.__protocol_for(protocol)
    case protocol
    when Class
      protocol
    when :actioncable_v1_json
      Protocols::ActioncableV1Json
    when :raw_websocket_json
      Protocols::RawWebSocketJson
    else
      raise ArgumentError, "Unknown protocol. Supported values are `:actioncable_v1_json` and `:raw_websocket_json`."
    end
  end

  # @private
  def self.__build_handler(protocol, router)
    klass = Class.new do
      def initialize(protocol, router)
        Iodine.on_state(:on_start) do
          unless Fiber.scheduler
            Fiber.set_scheduler(Rage::FiberScheduler.new)
          end
        end

        @protocol = protocol
        @router = router
        @log_processor = Rage.__log_processor
      end

      def on_open(connection)
        init_connection(connection)
        schedule_processing(connection) { |env| @protocol.on_open(connection, env, @router) }
      end

      def on_message(connection, data)
        schedule_processing(connection) { |env| @protocol.on_message(connection, env, data, @router) }
      end

      if protocol.respond_to?(:on_close)
        def on_close(connection)
          return unless ::Iodine.running?
          schedule_processing(connection) { |env| @protocol.on_close(connection, env, @router) }
          connection.env["rage.cable.queue"] << nil
        end
      end

      if protocol.respond_to?(:on_shutdown)
        def on_shutdown(connection)
          @protocol.on_shutdown(connection, @router)
        rescue => e
          log_error(e)
        end
      end

      private

      def init_connection(connection)
        queue = Queue.new
        fiber = Fiber.schedule do
          # `connection.env` is reset once the connection is closed; since messages are processed asynchronously,
          # a connection can already be closed by the time the message is processed, so we store `env` separately
          env = connection.env

          Rage.__log_processor.init_request_logger(env)

          loop do
            work = queue.shift
            break unless work

            work.call(env)
          rescue => e
            log_error(e)
          end
        end

        connection.env["rage.cable.fiber"] = fiber
        connection.env["rage.cable.queue"] = queue
      end

      def schedule_processing(connection, &block)
        connection.env["rage.cable.queue"] << block
      end

      def log_error(e)
        Rage.logger.error("Unhandled exception has occurred - #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        Rage::Errors.report(e)
      end
    end

    klass.new(protocol, router)
  end

  # Broadcast data directly to a named stream.
  #
  # @param stream [String] the name of the stream
  # @param data [Object] the object to send to the clients. This will later be encoded according to the protocol used.
  # @return [true]
  # @example
  #   Rage.cable.broadcast("chat", { message: "A new member has joined!" })
  def self.broadcast(stream, data)
    Rage::Telemetry.tracer.span_cable_stream_broadcast(stream:) do
      Relay.broadcast(stream, data)
      @__adapter&.publish(PUBSUB_BROADCASTER_ID, stream, data)
    end

    true
  end

  # @private
  module Relay
    def self.broadcast(stream, data)
      Rage::Cable.__protocols.each do |protocol|
        protocol.broadcast(stream, data)
      end
    end
  end

  # @!parse [ruby]
  #   # @abstract
  #   class WebSocketConnection
  #     # Write data to the connection.
  #     #
  #     # @param data [String] the data to write
  #     def write(data)
  #     end
  #
  #     # Subscribe to a channel.
  #     #
  #     # @param name [String] the channel name
  #     def subscribe(name)
  #     end
  #
  #     # Unsubscribe from a channel.
  #     #
  #     # @param name [String] the channel name
  #     def unsubscribe(name)
  #     end
  #
  #     # Close the connection.
  #     def close
  #     end
  #   end

  module Protocols
  end

  Protocol = Protocols
end

require_relative "protocols/base"
require_relative "protocols/actioncable_v1_json"
require_relative "protocols/raw_web_socket_json"
require_relative "channel"
require_relative "connection"
require_relative "router"
require_relative "remote_disconnect"

if Rage.config.internal.initialized?
  Rage::Cable.__initialize
else
  Rage.config.after_initialize { Rage::Cable.__initialize }
end

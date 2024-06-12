# frozen_string_literal: true

module Rage::Cable
  # Create a new Cable application.
  #
  # @example
  #   map "/cable" do
  #     run Rage.cable.application
  #   end
  def self.application
    protocol = Rage.config.cable.protocol
    protocol.init(__router)

    handler = __build_handler(protocol)
    accept_response = [0, protocol.protocol_definition, []]

    application = ->(env) do
      if env["rack.upgrade?"] == :websocket
        env["rack.upgrade"] = handler
        accept_response
      else
        [426, { "Connection" => "Upgrade", "Upgrade" => "websocket" }, []]
      end
    end

    Rage.with_middlewares(application, Rage.config.cable.middlewares)
  end

  # @private
  def self.__router
    @__router ||= Router.new
  end

  # @private
  def self.__build_handler(protocol)
    klass = Class.new do
      def initialize(protocol)
        @protocol = protocol
      end

      def on_open(connection)
        Fiber.schedule { @protocol.on_open(connection) }
      end

      def on_message(connection, data)
        Fiber.schedule { @protocol.on_message(connection, data) }
      end

      if protocol.respond_to?(:on_close)
        def on_close(connection)
          if ::Iodine.running?
            Fiber.schedule { @protocol.on_close(connection) }
          end
        end
      end

      if protocol.respond_to?(:on_shutdown)
        def on_shutdown(connection)
          @protocol.on_shutdown(connection)
        end
      end
    end

    klass.new(protocol)
  end

  # Broadcast data directly to a named stream.
  #
  # @param stream [String] the name of the stream
  # @param data [Object] the object to send to the clients. This will later be encoded according to the protocol used.
  # @example
  #   Rage.cable.broadcast("chat", { message: "A new member has joined!" })
  def self.broadcast(stream, data)
    Rage.config.cable.protocol.broadcast(stream, data)
  end

  # @private
  def self.debug_log
    if Rage.logger.debug?
      Rage.logger.tagged("cable") { Rage.logger.debug { yield } }
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
  #     # Close the connection.
  #     def close
  #     end
  #   end

  module Protocol
  end
end

require_relative "protocol/actioncable_v1_json"
require_relative "channel"
require_relative "connection"
require_relative "router"

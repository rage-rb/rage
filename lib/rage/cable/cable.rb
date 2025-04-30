# frozen_string_literal: true

module Rage::Cable
  # Create a new Cable application.
  #
  # @example
  #   map "/cable" do
  #     run Rage.cable.application
  #   end
  def self.application
    # explicitly initialize the adapter
    __adapter

    handler = __build_handler(__protocol)
    accept_response = [0, __protocol.protocol_definition, []]

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
  def self.__protocol
    @__protocol ||= Rage.config.cable.protocol.tap { |protocol| protocol.init(__router) }
  end

  def self.__adapter
    @__adapter ||= Rage.config.cable.adapter
  end

  # @private
  def self.__build_handler(protocol)
    klass = Class.new do
      def initialize(protocol)
        Iodine.on_state(:on_start) do
          unless Fiber.scheduler
            Fiber.set_scheduler(Rage::FiberScheduler.new)
          end
        end

        @protocol = protocol
        @default_log_context = {}.freeze
      end

      def on_open(connection)
        connection.env["rage.request_id"] ||= Iodine::Rack::Utils.gen_request_tag
        schedule_fiber(connection) { @protocol.on_open(connection) }
      end

      def on_message(connection, data)
        schedule_fiber(connection) { @protocol.on_message(connection, data) }
      end

      if protocol.respond_to?(:on_close)
        def on_close(connection)
          return unless ::Iodine.running?
          schedule_fiber(connection) { @protocol.on_close(connection) }
        end
      end

      if protocol.respond_to?(:on_shutdown)
        def on_shutdown(connection)
          @protocol.on_shutdown(connection)
        rescue => e
          log_error(e)
        end
      end

      private

      def schedule_fiber(connection)
        Fiber.schedule do
          Thread.current[:rage_logger] = { tags: [connection.env["rage.request_id"]], context: @default_log_context }
          yield
        rescue => e
          log_error(e)
        end
      end

      def log_error(e)
        Rage.logger.error("Unhandled exception has occured - #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      end
    end

    klass.new(protocol)
  end

  # Broadcast data directly to a named stream.
  #
  # @param stream [String] the name of the stream
  # @param data [Object] the object to send to the clients. This will later be encoded according to the protocol used.
  # @return [true]
  # @example
  #   Rage.cable.broadcast("chat", { message: "A new member has joined!" })
  def self.broadcast(stream, data)
    __protocol.broadcast(stream, data)
    __adapter&.publish(stream, data)

    true
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

  module Adapters
    autoload :Base, "rage/cable/adapters/base"
    autoload :Redis, "rage/cable/adapters/redis"
  end

  module Protocol
  end
end

require_relative "protocol/base"
require_relative "protocol/actioncable_v1_json"
require_relative "channel"
require_relative "connection"
require_relative "router"

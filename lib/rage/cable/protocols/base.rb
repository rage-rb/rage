# frozen_string_literal: true

require "digest"

##
# A protocol defines the structure, rules and semantics for exchanging data between the client and the server.
# A protocol class should inherit from {Rage::Cable::Protocols::Base} and implement the following methods:
#
# * `on_open`
# * `on_message`
# * `serialize`
# * `protocol_id`
#
# The optional methods are:
#
# * `protocol_definition`
# * `supports_rpc?`
# * `on_shutdown`
# * `on_close`
#
class Rage::Cable::Protocols::Base
  # @private
  HANDSHAKE_HEADERS = {}

  class << self
    def init
      # Hash<String(stream name) => Set<Hash>(subscription params)>
      @subscription_identifiers = Hash.new { |hash, key| hash[key] = Set.new }
      @sync_channel = "cable:#{protocol_id}:synchronize"

      Iodine.on_state(:pre_start) do
        # this is a fallback to synchronize subscription identifiers across different worker processes;
        # we expect connections to be distributed among all workers, so this code will almost never be called;
        # we also synchronize subscriptions with the master process so that the forks that are spun up instead
        # of the crashed ones also had access to the identifiers;
        Iodine.subscribe(@sync_channel) do |_, subscription_msg|
          stream_name, params = Rage::ParamsParser.json_parse(subscription_msg)
          @subscription_identifiers[stream_name] << params
        end
      end

      Iodine.on_state(:on_finish) do
        Iodine.unsubscribe(@sync_channel)
      end
    end

    def protocol_definition
      HANDSHAKE_HEADERS
    end

    # Subscribe to a stream.
    #
    # @param connection [Rage::Cable::WebSocketConnection] the connection object
    # @param name [String] the stream name
    # @param params [Hash] parameters associated with the client
    def subscribe(connection, name, params)
      connection.subscribe("cable:#{protocol_id}:#{name}:#{stream_id(params)}")

      unless @subscription_identifiers[name].include?(params)
        @subscription_identifiers[name] << params
        ::Iodine.publish(@sync_channel, [name, params].to_json)
      end
    end

    # Unsubscribe from a stream.
    #
    # @param connection [Rage::Cable::WebSocketConnection] the connection object
    # @param name [String] the stream name
    # @param params [Hash] parameters associated with the client
    def unsubscribe(connection, name, params)
      connection.unsubscribe("cable:#{protocol_id}:#{name}:#{stream_id(params)}")
    end

    # Broadcast data to all clients connected to a stream.
    #
    # @param name [String] the stream name
    # @param data [Object] the data to send
    def broadcast(name, data)
      @subscription_identifiers[name].each do |params|
        ::Iodine.publish("cable:#{protocol_id}:#{name}:#{stream_id(params)}", serialize(params, data))
      end
    end

    # Whether the protocol allows remote procedure calls.
    #
    # @return [Boolean]
    def supports_rpc?
      true
    end

    private

    def stream_id(params)
      Digest::MD5.hexdigest(params.to_s)
    end
  end # class << self
end

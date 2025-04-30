# frozen_string_literal: true

require "zlib"
require "set"

class Rage::Cable::Protocols::Base
  HANDSHAKE_HEADERS = {}

  # @param router [Rage::Cable::Router]
  def self.init(router)
    @router = router

    # Hash<String(stream name) => Set<Hash>(subscription params)>
    @subscription_identifiers = Hash.new { |hash, key| hash[key] = Set.new }

    Iodine.on_state(:pre_start) do
      # this is a fallback to synchronize subscription identifiers across different worker processes;
      # we expect connections to be distributed among all workers, so this code will almost never be called;
      # we also synchronize subscriptions with the master process so that the forks that are spun up instead
      # of the crashed ones also had access to the identifiers;
      Iodine.subscribe("cable:synchronize") do |_, subscription_msg|
        stream_name, params = Rage::ParamsParser.json_parse(subscription_msg)
        @subscription_identifiers[stream_name] << params
      end
    end

    Iodine.on_state(:on_finish) do
      Iodine.unsubscribe("cable:synchronize")
    end
  end

  def self.protocol_definition
    HANDSHAKE_HEADERS
  end

  # Subscribe to a stream.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param name [String] the stream name
  # @param params [Hash] parameters associated with the client
  def self.subscribe(connection, name, params)
    connection.subscribe("cable:#{name}:#{Zlib.crc32(params.to_s)}")

    unless @subscription_identifiers[name].include?(params)
      @subscription_identifiers[name] << params
      ::Iodine.publish("cable:synchronize", [name, params].to_json)
    end
  end

  # Broadcast data to all clients connected to a stream.
  #
  # @param name [String] the stream name
  # @param data [Object] the data to send
  def self.broadcast(name, data)
    @subscription_identifiers[name].each do |params|
      ::Iodine.publish("cable:#{name}:#{Zlib.crc32(params.to_s)}", serialize(params, data))
    end
  end
end

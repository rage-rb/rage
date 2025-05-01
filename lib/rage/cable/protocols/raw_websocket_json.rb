# frozen_string_literal: true

##
# The `RawWebsocketJson` protocol allows a direct connection to a {Rage::Cable} application using the native
# `WebSocket` object. With this protocol, each WebSocket connection directly corresponds to a single
# channel subscription. As a result, clients are automatically subscribed to a channel as soon as
# they establish a connection.
#
# @see Rage::Cable::Protocols::ActioncableV1Json
#
class Rage::Cable::Protocols::RawWebsocketJson < Rage::Cable::Protocols::Base
  # identifiers are used to distinguish between different channels that share a single connection;
  # since the raw protocol uses a single connection for each channel, identifiers are not necessary
  IDENTIFIER = ""

  module MESSAGES
    UNAUTHORIZED = { err: "unauthorized" }.to_json
    REJECTED = { err: "subscription rejected" }.to_json
    INVALID = { err: "invalid channel name" }.to_json
    UNKNOWN = { err: "unknown action" }.to_json
  end

  DEFAULT_PARAMS = {}.freeze

  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  def self.on_open(connection)
    accepted = @router.process_connection(connection)

    unless accepted
      connection.write(MESSAGES::UNAUTHORIZED)
      connection.close
      return
    end

    channel_id = connection.env["PATH_INFO"].split("/")[-1]
    channel_name = "#{channel_id.capitalize! || channel_id}Channel"

    query_string = connection.env["QUERY_STRING"]
    params = query_string == "" ? DEFAULT_PARAMS : Iodine::Rack::Utils.parse_nested_query(query_string)

    status = @router.process_subscription(connection, IDENTIFIER, channel_name, params)

    if status == :rejected
      connection.write(MESSAGES::REJECTED)
      connection.close
    elsif status == :invalid
      connection.write(MESSAGES::INVALID)
      connection.close
    end
  end

  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param raw_data [String] the message body
  def self.on_message(connection, raw_data)
    if raw_data == "ping"
      connection.write("pong")
      return
    end

    data = JSON.parse(raw_data)

    message_status = @router.process_message(connection, IDENTIFIER, :receive, data)
    unless message_status == :processed
      connection.write(MESSAGES::UNKNOWN)
    end
  end

  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  def self.on_close(connection)
    @router.process_disconnection(connection)
  end

  # @param data [Object] the object to serialize
  def self.serialize(_, data)
    data.to_json
  end
end

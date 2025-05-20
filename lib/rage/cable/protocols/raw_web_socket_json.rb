# frozen_string_literal: true

##
# The `RawWebSocketJson` protocol allows a direct connection to a {Rage::Cable} application using the native
# `WebSocket` object. With this protocol, each WebSocket connection directly corresponds to a single
# channel subscription. As a result, clients are automatically subscribed to a channel as soon as
# they establish a connection.
#
# Heartbeats are also supported - the server will respond with `pong` to every `ping` message. Additionally,
# all ping messages are buffered and processed once a second, which means it can take up to a second for
# the server to respond to a `ping`.
#
# @see Rage::Cable::Protocols::Base
#
# @example Server side
#   class TodoItemsChannel
#     def subscribed
#       stream_from "todo-items-#{params[:user_id]}"
#     end
#
#     def receive(data)
#       puts "New Todo item: #{data}"
#     end
#   end
#
# @example Client side
#   socket = new WebSocket("ws://localhost:3000/cable/todo_items?user_id=123")
#   socket.send(JSON.stringify({ item: "New Item" }))
#
class Rage::Cable::Protocols::RawWebSocketJson < Rage::Cable::Protocols::Base
  # identifiers are used to distinguish between different channels that share a single connection;
  # since the raw protocol uses a single connection for each channel, identifiers are not necessary
  IDENTIFIER = ""
  private_constant :IDENTIFIER

  module MESSAGES
    UNAUTHORIZED = { err: "unauthorized" }.to_json
    REJECTED = { err: "subscription rejected" }.to_json
    INVALID = { err: "invalid channel name" }.to_json
    UNKNOWN = { err: "unknown action" }.to_json
  end
  private_constant :MESSAGES

  DEFAULT_PARAMS = {}.freeze
  private_constant :DEFAULT_PARAMS

  def self.init(router)
    super

    @ping_connections = Set.new

    Iodine.on_state(:on_start) do
      Iodine.run_every(1_000) do
        @ping_connections.each_slice(500) do |slice|
          Iodine.defer { slice.each { |connection| connection.write("pong") } }
        end

        @ping_connections.clear
      end
    end
  end

  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  def self.on_open(connection)
    accepted = @router.process_connection(connection)

    unless accepted
      connection.write(MESSAGES::UNAUTHORIZED)
      connection.close
      return
    end

    channel_id = connection.env["PATH_INFO"].split("/")[-1]

    channel_name = if channel_id.end_with?("Channel")
      channel_id
    else
      if channel_id.include?("_")
        tmp = ""
        channel_id.split("_") { |segment| tmp += segment.capitalize! || segment }
        channel_id = tmp
      else
        channel_id.capitalize!
      end

      "#{channel_id}Channel"
    end

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
      @ping_connections << connection
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

  # @return [Boolean]
  def self.supports_rpc?
    false
  end

  # @private
  # The base implementation groups connection subscriptions by `params`;
  # however, with `RawWebSocketJson`, params are not part of the payload (see {serialize})
  # and we can disable grouping in exchange for better performance
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param name [String] the stream name
  def self.subscribe(connection, name, _)
    super(connection, name, "")
  end
end

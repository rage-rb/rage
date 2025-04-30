# frozen_string_literal: true

##
# A protocol defines the structure, rules and semantics for exchanging data between the client and the server.
# The protocol class should inherit from {Rage::Cable::Protocols::Base} and respond to the following methods:
#
# * `protocol_definition`
# * `init`
# * `on_open`
# * `on_message`
# * `serialize`
#
# The two optional methods are:
#
# * `on_shutdown`
# * `on_close`
#
class Rage::Cable::Protocols::ActioncableV1Json < Rage::Cable::Protocols::Base
  module TYPE
    WELCOME = "welcome"
    DISCONNECT = "disconnect"
    PING = "ping"
    CONFIRM = "confirm_subscription"
    REJECT = "reject_subscription"
  end

  module REASON
    UNAUTHORIZED = "unauthorized"
    INVALID = "invalid_request"
  end

  module COMMAND
    SUBSCRIBE = "subscribe"
    MESSAGE = "message"
  end

  module MESSAGES
    WELCOME = { type: TYPE::WELCOME }.to_json
    UNAUTHORIZED = { type: TYPE::DISCONNECT, reason: REASON::UNAUTHORIZED, reconnect: false }.to_json
    INVALID = { type: TYPE::DISCONNECT, reason: REASON::INVALID, reconnect: true }.to_json
  end

  HANDSHAKE_HEADERS = { "Sec-WebSocket-Protocol" => "actioncable-v1-json" }

  # The method defines the headers to send to the client after the handshake process.
  def self.protocol_definition
    HANDSHAKE_HEADERS
  end

  # This method serves as a constructor to prepare the object or set up recurring tasks (e.g. heartbeats).
  #
  # @param router [Rage::Cable::Router]
  def self.init(router)
    super

    Iodine.on_state(:on_start) do
      ping_counter = Time.now.to_i

      Iodine.run_every(3000) do
        ping_counter += 1
        Iodine.publish("cable:ping", { type: TYPE::PING, message: ping_counter }.to_json, Iodine::PubSub::PROCESS)
      end
    end
  end

  # The method is called any time a new WebSocket connection is established.
  # It is expected to call {Rage::Cable::Router#process_connection} and handle its return value.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @see Rage::Cable::Router
  def self.on_open(connection)
    accepted = @router.process_connection(connection)

    if accepted
      connection.subscribe("cable:ping")
      connection.write(MESSAGES::WELCOME)
    else
      connection.write(MESSAGES::UNAUTHORIZED)
      connection.close
    end
  end

  # The method processes messages from existing connections. It should parse the message, call either
  # {Rage::Cable::Router#process_subscription} or {Rage::Cable::Router#process_message}, and handle its return value.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param raw_data [String] the message body
  # @see Rage::Cable::Router
  def self.on_message(connection, raw_data)
    parsed_data = Rage::ParamsParser.json_parse(raw_data)

    command, identifier = parsed_data[:command], parsed_data[:identifier]
    params = Rage::ParamsParser.json_parse(identifier)

    # process subscription messages
    if command == COMMAND::SUBSCRIBE
      status = @router.process_subscription(connection, identifier, params[:channel], params)
      if status == :subscribed
        connection.write({ identifier: identifier, type: TYPE::CONFIRM }.to_json)
      elsif status == :rejected
        connection.write({ identifier: identifier, type: TYPE::REJECT }.to_json)
      elsif status == :invalid
        connection.write(MESSAGES::INVALID)
      end

      return
    end

    # process data messages;
    # plain `JSON` is used here to conform with the ActionCable API that passes `data` as a Hash with string keys;
    data = JSON.parse(parsed_data[:data])

    message_status = if command == COMMAND::MESSAGE && data.has_key?("action")
      @router.process_message(connection, identifier, data["action"].to_sym, data)

    elsif command == COMMAND::MESSAGE
      @router.process_message(connection, identifier, :receive, data)
    end

    unless message_status == :processed
      connection.write(MESSAGES::INVALID)
    end
  end

  # The method should process client disconnections and call {Rage::Cable::Router#process_disconnection}.
  #
  # @note This method is optional.
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @see Rage::Cable::Router
  def self.on_close(connection)
    @router.process_disconnection(connection)
  end

  # Serialize a Ruby object into the format the client would understand.
  #
  # @param params [Hash] parameters associated with the client
  # @param data [Object] the object to serialize
  def self.serialize(params, data)
    { identifier: params.to_json, message: data }.to_json
  end
end

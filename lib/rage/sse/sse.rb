# frozen_string_literal: true

module Rage::SSE
  # A factory method for creating Server-Sent Events.
  #
  # @param data [String, #to_json] The `data` field for the SSE event. If the object provided is not a string, it will be serialized to JSON.
  # @param id [String, nil] The `id` field for the SSE event. This can be used to track messages.
  # @param event [String, nil] The `event` field for the SSE event. This can be used to define custom event types.
  # @param retry [Integer, nil] The `retry` field for the SSE event, in milliseconds. This value is used to instruct the client how long to wait before attempting to reconnect.
  # @return [Message] The formatted SSE event.
  # @example
  #   render sse: Rage::SSE.message(current_user.profile, id: current_user.id)
  def self.message(data, id: nil, event: nil, retry: nil)
    Message.new(data:, id:, event:, retry:)
  end

  # A factory method for creating unbounded SSE streams.
  #
  # @param streamable [#id, String, Symbol, Numeric, Array] An object to generate the stream name from.
  # @return [Stream] A new SSE stream instance.
  # @example
  #   render sse: Rage::SSE.stream("#{current_user.id}-notifications")
  # @example
  #   render sse: Rage::SSE.stream([current_user.id, "notifications"])
  def self.stream(streamable)
    Stream.new(streamable:)
  end

  # @private
  def self.__serialize(data)
    if data.is_a?(String)
      data.include?("\n") ? Message.new(data:).to_s : "data: #{data}\n\n"
    elsif data.is_a?(Message)
      data.to_s
    else
      "data: #{data.to_json}\n\n"
    end
  end

  # @private
  def self.__adapter=(adapter)
    @__adapter = adapter
  end

  # @private
  CLOSE_STREAM_MSG = "rage-close-stream"

  # @private
  PUBSUB_BROADCASTER_ID = "sse"

  # Close an unbounded SSE stream. Unbounded streams will remain open until either the client disconnects or the server explicitly closes them.
  #
  # @param streamable [#id, String, Symbol, Numeric, Array] The identifier of the stream to close.
  # @example
  #   Rage::SSE.close_stream("#{current_user.id}-notifications")
  # @example
  #   Rage::SSE.close_stream([current_user.id, "notifications"])
  def self.close_stream(streamable)
    stream_name = Rage::Internal.stream_name_for(streamable)

    InternalBroadcast.broadcast(stream_name, CLOSE_STREAM_MSG, Iodine::PubSub::CLUSTER) if Iodine.running?
    @__adapter&.publish(PUBSUB_BROADCASTER_ID, stream_name, CLOSE_STREAM_MSG)
  end

  # Broadcast a message to all clients subscribed to a given stream.
  #
  # @param streamable [#id, String, Symbol, Numeric, Array] The identifier of the stream to broadcast to.
  # @param data [String, #to_json, Message] The message to broadcast.
  # @example
  #   Rage::SSE.broadcast("#{current_user.id}-notifications", "You have a new notification!")
  # @example
  #   Rage::SSE.broadcast([current_user.id, "notifications"], { title: "New Notification", body: "You have a new notification!" })
  def self.broadcast(streamable, data)
    Rage::Telemetry.tracer.span_sse_stream_broadcast(stream: streamable) do
      stream_name = Rage::Internal.stream_name_for(streamable)
      serialized_data = __serialize(data)

      InternalBroadcast.broadcast(stream_name, serialized_data, Iodine::PubSub::CLUSTER) if Iodine.running?
      @__adapter&.publish(PUBSUB_BROADCASTER_ID, stream_name, serialized_data)
    end

    true
  end

  # @private
  module InternalBroadcast
    def self.broadcast(stream_name, data, engine)
      if Rage::SSE::Stream.__message_buffer.has_key?(stream_name)
        Rage::SSE::Stream.__store_message(stream_name, data)
      end

      Iodine.publish("sse:#{stream_name}", data, engine)
    end
  end

  # @private
  module Relay
    def self.broadcast(stream_name, data)
      Iodine.publish("sse-relay", "#{stream_name}\x00#{data}")
    end
  end
end

require_relative "application"
require_relative "connection_proxy"
require_relative "message"
require_relative "stream"

Rage.config.after_initialize do
  if (adapter = Rage.config.pubsub.adapter)
    Iodine.on_state(:on_start) do
      Iodine.subscribe("sse-relay") do |_, msg|
        stream_name, data = msg.split("\x00", 2)
        Rage::SSE::InternalBroadcast.broadcast(stream_name, data, Iodine::PubSub::PROCESS)
      end
    end

    Iodine.on_state(:on_finish) do
      Iodine.unsubscribe("sse-relay")
    end

    adapter.add_broadcaster(Rage::SSE::PUBSUB_BROADCASTER_ID, Rage::SSE::Relay)
    Rage::SSE.__adapter = adapter
  end
end

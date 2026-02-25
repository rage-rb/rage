# frozen_string_literal: true

module Rage::SSE
  # Factory method to create SSE events.
  #
  # @param data [String, #to_json] The `data` field of the SSE event. If it's an object, it will be serialized to JSON.
  # @param id [String, nil] The `id` field of the SSE event.
  # @param event [String, nil] The `event` field of the SSE event.
  # @param retry [Integer, nil] The `retry` field of the SSE event, in milliseconds.
  # @return [Message] The created SSE event.
  # @example
  #   Rage::SSE.message(current_user.profile, id: current_user.id)
  def self.message(data, id: nil, event: nil, retry: nil)
    Message.new(data:, id:, event:, retry:)
  end

  def self.__serialize(data)
    if data.is_a?(String)
      "data: #{data}\n\n"
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
  def self.__adapter
    @__adapter
  end

  # TODO: telemetry
  def self.broadcast(stream, data)
    InternalBroadcast.broadcast(stream, data)
    __adapter&.publish(stream, data)
  end

  # @private
  module InternalBroadcast
    def self.broadcast(stream, data)
      Iodine.publish("sse:#{stream}", Rage::SSE.__serialize(data))
    end
  end
end

require_relative "application"
require_relative "connection_proxy"
require_relative "message"
require_relative "stream"

# Rage::SSE.__adapter = Rage::PubSub::Adapters::Redis.new("rage:sse:messages", Rage::SSE::InternalBroadcast, {})

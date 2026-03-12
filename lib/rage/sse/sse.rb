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

  # @private
  def self.__serialize(data)
    if data.is_a?(String)
      "data: #{data}\n\n"
    elsif data.is_a?(Message)
      data.to_s
    else
      "data: #{data.to_json}\n\n"
    end
  end
end

require_relative "application"
require_relative "connection_proxy"
require_relative "message"

# frozen_string_literal: true

##
# The class representing an unbounded Server-Sent Events stream. It allows for broadcasting messages to all connected clients subscribed to the stream.
#
# Create a stream:
#
# ```ruby
# render sse: Rage::SSE.stream([current_user, "notifications"])
# ```
#
# Broadcast a message to all connections subscribed to the stream:
# ```ruby
# Rage::SSE.broadcast([current_user, "notifications"], "You have a new notification!")
# ```
#
# Close the stream:
# ```ruby
# Rage::SSE.close_stream([current_user, "notifications"])
# ```
#
# Messages to known streams are buffered until a connection is fully established:
# ```ruby
# # Create a stream first
# stream = Rage::SSE.stream([current_user, "notifications"])
#
# # No connection yet, but the message is buffered
# Rage::SSE.broadcast([current_user, "notifications"], "You have a new notification!")
#
# # Establish a connection, which will claim the buffered message
# render sse: stream
# ```
#
class Rage::SSE::Stream
  class << self
    # @private
    def __message_buffer
      @__message_buffer ||= Hash.new { |h, k| h[k] = {} }
    end

    # @private
    def __store_message(stream, message)
      __message_buffer[stream].transform_values! do |buffer|
        buffer.frozen? ? [message] : buffer.push(message)
      end
    end

    # @private
    def __claim_buffered_messages(stream)
      messages = __message_buffer[stream.name][stream.owner] if __message_buffer.has_key?(stream.name)
      cleanup_message_buffer

      messages
    end

    private

    def cleanup_message_buffer
      __message_buffer.delete_if do |_, connection_buffers|
        connection_buffers.keys.none?(&:alive?)
      end
    end
  end

  DEFAULT_BUFFER = [].freeze
  private_constant :DEFAULT_BUFFER

  # @private
  attr_reader :name, :owner

  # @param streamable [#id, String, Symbol, Numeric, Array] an object that will be used to generate the stream name
  def initialize(streamable:)
    @name = Rage::Internal.stream_name_for(streamable)
    @owner = Fiber.current

    self.class.__message_buffer[@name][@owner] ||= DEFAULT_BUFFER
  end
end

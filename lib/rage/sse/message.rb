# frozen_string_literal: true

# Represents a single Server-Sent Event. This class allows you to define the `id`, `event`, and `retry` fields for an SSE message.
#
# @!attribute id
#   @return [String] The `id` field for the SSE event. This can be used to track messages.
# @!attribute event
#   @return [String] The `event` field for the SSE event. This can be used to define custom event types.
# @!attribute retry
#   @return [Integer] The `retry` field for the SSE event, in milliseconds. This value is a suggestion for the client about how long to wait before reconnecting.
# @!attribute data
#   @return [String, #to_json] The `data` field for the SSE event. If the object provided is not a string, it will be serialized to JSON.
Rage::SSE::Message = Struct.new(:id, :event, :retry, :data, keyword_init: true) do
  def to_s
    data_entry = if !data.is_a?(String)
      "data: #{data.to_json}\n"
    elsif data.include?("\n")
      data.split("\n").map { |d| "data: #{d}\n" }.join
    else
      "data: #{data}\n"
    end

    "#{data_entry}#{"id: #{id}\n" if id}#{"event: #{event}\n" if event}#{"retry: #{self.retry.to_i}\n" if self.retry && self.retry.to_i > 0}\n"
  end
end

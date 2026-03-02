# frozen_string_literal: true

# A class representing an SSE event. Use it to specify the `id`, `event`, and `retry` fields in an SSE.
#
# @!attribute id
#   @return [String] The `id` field of the SSE event.
# @!attribute event
#   @return [String] The `event` field of the SSE event.
# @!attribute retry
#   @return [Integer] The `retry` field of the SSE event, in milliseconds.
# @!attribute data
#   @return [String, #to_json] The `data` field of the SSE event. If it's an object, it will be serialized to JSON.
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

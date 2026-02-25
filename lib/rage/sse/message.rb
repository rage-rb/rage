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
    str = ""

    str << "id: #{id}\n" if id
    str << "event: #{event}\n" if event
    str << "retry: #{self.retry}\n" if self.retry
    str << "data: #{data.is_a?(String) ? data : data.to_json}\n" if data # TODO: multiline

    str + "\n"
  end
end

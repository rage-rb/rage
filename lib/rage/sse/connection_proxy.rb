# frozen_string_literal: true

##
# This class acts as a proxy for the underlying SSE connection, providing a simplified and safe interface for interacting with the stream.
# It ensures that operations are only performed on an open connection and abstracts away the direct connection handling.
#
# Example:
#
# ```ruby
# render sse: ->(connection) do
#   # `connection` is an instance of Rage::SSE::ConnectionProxy
# end
# ```
#
class Rage::SSE::ConnectionProxy
  # @private
  def initialize(connection)
    @connection = connection
  end

  # Writes data to the SSE stream.
  # @param data [#to_s]
  # @raise [IOError] if the stream is already closed.
  def write(data)
    raise IOError, "closed stream" unless @connection.open?
    @connection.write(data.to_s)
  end

  alias_method :<<, :write

  # Closes the SSE stream.
  def close
    @connection.close
  end

  alias_method :close_write, :close

  # Checks if the SSE stream is closed.
  # @return [Boolean]
  def closed?
    !@connection.open?
  end

  # A no-op method to maintain interface compatibility.
  # Flushing is handled by the underlying connection.
  # @raise [IOError] if the stream is already closed.
  def flush
    raise IOError, "closed stream" unless @connection.open?
  end

  # A no-op method to maintain interface compatibility.
  # Reading from an SSE stream is not supported on the server side.
  def read(...)
  end

  # A no-op method to maintain interface compatibility.
  # Reading from an SSE stream is not supported on the server side.
  def close_read
  end
end

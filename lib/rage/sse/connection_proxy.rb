# frozen_string_literal: true

class Rage::SSE::ConnectionProxy
  def initialize(connection)
    @connection = connection
  end

  def write(data)
    raise IOError, "closed stream" unless @connection.open?
    @connection.write(data)
  end

  alias_method :<<, :write

  def close
    @connection.close
  end

  alias_method :close_write, :close

  def closed?
    !@connection.open?
  end

  def flush
    raise IOError, "closed stream" unless @connection.open?
  end

  def read(...)
  end

  def close_read
  end
end

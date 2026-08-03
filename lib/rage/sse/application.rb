# frozen_string_literal: true

# @private
# This class is responsible for handling the lifecycle of an SSE connection.
# It determines the type of SSE stream and manages the data flow.
#
class Rage::SSE::Application
  def initialize(stream)
    @stream = stream

    @type = if @stream.is_a?(Enumerator)
      :stream
    elsif @stream.is_a?(Proc)
      :manual
    elsif @stream.is_a?(Rage::SSE::Stream)
      :broadcast
    else
      :single
    end

    @log_tags, @log_context = Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context]
  end

  def on_open(connection)
    if @type == :single
      send_data(connection)
    elsif @type == :broadcast
      start_broadcast_stream(connection)
    else
      start_stream(connection)
    end
  end

  private

  def send_data(connection)
    Rage::Telemetry.tracer.span_sse_stream_process(connection:, type: @type) do
      connection.write(Rage::SSE.__serialize(@stream))
    end
  ensure
    connection.close
  end

  def start_broadcast_stream(connection)
    channel = "sse:#{@stream.name}"

    connection.subscribe(channel) do |_, msg|
      msg == Rage::SSE::CLOSE_STREAM_MSG ? connection.close : connection.write(msg)
    end

    buffered_messages = Rage::SSE::Stream.__claim_buffered_messages(@stream)
    buffered_messages&.each do |msg|
      msg == Rage::SSE::CLOSE_STREAM_MSG ? connection.close : connection.write(msg)
    end
  end

  def start_stream(connection)
    Fiber.schedule do
      Iodine.task_inc!
      Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context] = @log_tags, @log_context
      Rage::Telemetry.tracer.span_sse_stream_process(connection:, type: @type) do
        @type == :stream ? start_formatted_stream(connection) : start_raw_stream(connection)
      end
    rescue => e
      Rage.logger.error("SSE stream failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      Rage::Errors.report(e)
    ensure
      Iodine.task_dec!
    end
  end

  def start_formatted_stream(connection)
    @stream.each do |event|
      break if !connection.open?
      connection.write(Rage::SSE.__serialize(event)) if event
    end
  ensure
    connection.close
  end

  def start_raw_stream(connection)
    @stream.call(Rage::SSE::ConnectionProxy.new(connection))
  rescue => e
    connection.close if connection.open?
    raise e
  end
end

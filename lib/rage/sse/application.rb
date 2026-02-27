# frozen_string_literal: true

# @private
class Rage::SSE::Application
  def initialize(stream)
    @stream = stream

    @type = if stream.is_a?(Enumerator)
      @streamer = create_enum_streamer
      :enum
    elsif stream.is_a?(Proc)
      @streamer = create_proc_streamer
      :proc
    elsif stream.is_a?(Rage::SSE::Stream)
      :stream
    else
      :object
    end
  end

  def on_open(connection)
    case @type
    when :enum, :proc
      @streamer.resume(connection)
    when :stream
      connection.subscribe("sse:#{@stream.id}") # TODO: hash? # TODO: broadcast right away?
    when :object
      connection.write(Rage::SSE.__serialize(@stream))
      connection.close
    end
  end

  private

  def create_enum_streamer
    Fiber.schedule do
      connection = Fiber.yield

      @stream.each do |event|
        break if !connection.open?
        connection.write(Rage::SSE.__serialize(event)) if event
      end
    rescue => e
      Rage.logger.error("SSE stream failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
    ensure
      connection.close
    end
  end

  def create_proc_streamer
    Fiber.schedule do
      connection = Fiber.yield
      @stream.call(Rage::SSE::ConnectionProxy.new(connection))
    rescue => e
      Rage.logger.error("SSE stream failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
    end
  end
end

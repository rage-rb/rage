# frozen_string_literal: true

class SseController < RageController::API
  def object
    render sse: { status: "ok", count: 42 }
  end

  def stream
    sleep 0.1

    stream = Enumerator.new do |y|
      y << "first"
      sleep 0.1

      y << Rage::SSE.message("second", id: "2", event: "update")
      sleep 0.1

      y << nil
      sleep 0.1

      y << { data: "third" }
      sleep 0.1
    end

    render sse: stream
  end

  def proc
    render sse: ->(conn) {
      conn.write("data: hello\n\n")
      conn.write(Rage::SSE.message("world"))
      conn.close
    }
  end

  def broadcast
    stream = Rage::SSE.stream("test-stream")
    Rage::SSE.broadcast("test-stream", "test message")

    4.times { BroadcastToStream.enqueue }
    CloseStream.enqueue(delay: 0.5)

    render sse: stream
  end

  def subscribe
    render sse: Rage::SSE.stream("test-stream")
  end
end

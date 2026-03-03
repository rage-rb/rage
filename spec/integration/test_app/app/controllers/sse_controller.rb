# frozen_string_literal: true

class SseController < RageController::API
  def object
    render sse: { status: "ok", count: 42 }
  end

  def stream
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
end

class BroadcastToStream
  include Rage::Deferred::Task

  def perform
    Rage::SSE.broadcast("test-stream", "test message")
  end
end

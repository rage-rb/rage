class CloseStream
  include Rage::Deferred::Task

  def perform
    Rage::SSE.close_stream("test-stream")
  end
end

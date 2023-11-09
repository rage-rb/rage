class Rage::Configuration
  def config = self

  def server
    @server ||= Server.new
  end

  class Server
    attr_accessor :port, :workers_count
    attr_reader :threads_count

    def initialize
      @threads_count = 1
      @workers_count = -1
      @port = 3000
    end
  end
end

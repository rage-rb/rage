class Rage::Configuration
  attr_accessor :port, :workers_count
  attr_reader :threads_count

  def initialize
    @threads_count = 1
    @workers_count = -1
    @port = 3000
  end
end

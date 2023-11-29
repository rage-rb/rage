class Rage::Configuration
  attr_accessor :logger, :log_formatter, :log_level

  # used in DSL
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

  def __finalize
    @logger ||= Rage::Logger.new(nil)
    @logger.formatter = @log_formatter if @logger && @log_formatter
    @logger.level = @log_level if @logger && @log_level
  end
end

class Rage::Configuration
  attr_accessor :logger, :log_formatter, :log_level

  # used in DSL
  def config = self

  def server
    @server ||= Server.new
  end

  def middleware
    @middleware ||= Middleware.new
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

  class Middleware
    attr_reader :middlewares

    def initialize
      @middlewares = [[Rage::FiberWrapper]]
    end

    def use(new_middleware, *args, &block)
      insert_after(@middlewares.length - 1, new_middleware, *args, &block)
    end

    def insert_before(existing_middleware, new_middleware, *args, &block)
      index = find_middleware_index(existing_middleware)
      @middlewares = (@middlewares[0...index] + [[new_middleware, args, block]] + @middlewares[index..]).uniq(&:first)
    end

    def insert_after(existing_middleware, new_middleware, *args, &block)
      index = find_middleware_index(existing_middleware)
      @middlewares = (@middlewares[0..index] + [[new_middleware, args, block]] + @middlewares[index + 1..]).uniq(&:first)
    end

    private

    def find_middleware_index(middleware)
      if middleware.is_a?(Integer)
        if middleware < 0 || middleware >= @middlewares.length
          raise ArgumentError, "Middleware index should be in the (0...#{@middlewares.length}) range"
        end
        middleware
      else
        @middlewares.index { |m, _, _| m == middleware }.tap do |i|
          raise ArgumentError, "Couldn't find #{middleware} in the middleware stack" unless i
        end
      end
    end
  end

  def __finalize
    @logger ||= Rage::Logger.new(nil)
    @logger.formatter = @log_formatter if @logger && @log_formatter
    @logger.level = @log_level if @logger && @log_level
  end
end

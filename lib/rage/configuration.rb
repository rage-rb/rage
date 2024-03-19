# frozen_string_literal: true

##
# # General Configuration
#
# • _config.logger_
#
# > The logger that will be used for `Rage.logger` and any related `Rage` logging. Custom loggers should implement Ruby's {https://ruby-doc.org/3.2.2/stdlibs/logger/Logger.html#class-Logger-label-Entries Logger} interface.
#
# • _config.log_formatter_
#
# > The formatter of the Rage logger. Built in options include `Rage::TextFormatter` and `Rage::JSONFormatter`. Defaults to an instance of `Rage::TextFormatter`.
#
# • _config.log_level_
#
# > Defines the verbosity of the Rage logger. This option defaults to `:debug` for all environments except production, where it defaults to `:info`. The available log levels are: `:debug`, `:info`, `:warn`, `:error`, `:fatal`, and `:unknown`.
#
# # Middleware Configuration
#
# • _config.middleware.use_
#
# > Adds a middleware to the top of the middleware stack. **This is the recommended way of adding a middleware.**
# > ```
# config.middleware.use Rack::Cors do
#   allow do
#     origins "*"
#     resource "*", headers: :any
#   end
# end
# > ```
#
# • _config.middleware.insert_before_
#
# > Adds middleware at a specified position before another middleware. The position can be either an index or another middleware.
#
# > **_❗️Heads up:_** By default, Rage always uses the `Rage::FiberWrapper` middleware, which wraps every request in a separate fiber. Make sure to always have this middleware in the top of the stack. Placing other middlewares in front may lead to undefined behavior.
#
# > ```
# config.middleware.insert_before Rack::Head, Magical::Unicorns
# config.middleware.insert_before 0, Magical::Unicorns
# > ```
#
# • _config.middleware.insert_after_
#
# > Adds middleware at a specified position after another middleware. The position can be either an index or another middleware.
#
# > ```
# config.middleware.insert_after Rack::Head, Magical::Unicorns
# > ```
#
# # Server Configuration
#
# _• config.server.max_clients_
#
# > Limits the number of simultaneous connections the server can accept. Defaults to the maximum number of open files.
#
# > **_❗️Heads up:_** Decreasing this number is almost never a good idea. Depending on your application specifics, you are encouraged to use other methods to limit the number of concurrent connections:
#
# > 1. If your application is exposed to the public, you may want to use a cloud rate limiter, like {https://developers.cloudflare.com/waf Cloudflare WAF} or {https://docs.fastly.com/en/ngwaf Fastly WAF}.
# > 2. Otherwise, consider using tools like {https://github.com/rack/rack-attack Rack::Attack} or {https://github.com/mperham/connection_pool connection_pool}.
#
# > ```
# # Limit the amount of connections your application can accept
# config.middleware.use Rack::Attack
# Rack::Attack.throttle("req/ip", limit: 300, period: 5.minutes) do |req|
#   req.ip
# end
# #
# # Limit the amount of connections to a specific resource
# HTTP = ConnectionPool.new(size: 5, timeout: 5) { Net::HTTP }
# HTTP.with do |conn|
#   conn.get("/my-resource")
# end
# > ```
#
# • _config.server.port_
#
# > Specifies what port the server will listen on.
#
# • _config.server.workers_count_
#
# > Specifies the number of server processes to run.
#
# • _config.server.timeout_
#
# > Specifies connection timeout.
#
class Rage::Configuration
  attr_accessor :logger
  attr_reader :log_formatter, :log_level

  # used in DSL
  def config = self

  def log_formatter=(formatter)
    raise "Custom log formatter should respond to `#call`" unless formatter.respond_to?(:call)
    @log_formatter = formatter
  end

  def log_level=(level)
    @log_level = level.is_a?(Symbol) ? Logger.const_get(level.to_s.upcase) : level
  end

  def server
    @server ||= Server.new
  end

  def middleware
    @middleware ||= Middleware.new
  end

  def internal
    @internal ||= Internal.new
  end

  class Server
    attr_accessor :port, :workers_count, :timeout, :max_clients
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
      if index == 0 && @middlewares[0][0] == Rage::FiberWrapper
        puts("Warning: inserting #{new_middleware} before Rage::FiberWrapper may lead to undefined behavior.")
      end
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

  # @private
  class Internal
    attr_accessor :rails_mode, :rails_console

    def inspect
      "#<#{self.class.name}>"
    end
  end

  # @private
  def __finalize
    if @logger
      @logger.formatter = @log_formatter if @log_formatter
      @logger.level = @log_level if @log_level
    else
      @logger = Rage::Logger.new(nil)
    end
  end
end

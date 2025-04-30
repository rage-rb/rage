# frozen_string_literal: true

require "yaml"
require "erb"

##
# `Rage.configure` can be used to adjust the behavior of your Rage application:
#
# ```ruby
# Rage.configure do
#   config.logger = Rage::Logger.new(STDOUT)
#   config.server.workers_count = 2
# end
# ```
#
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
# • _config.secret_key_base_
#
# > The `secret_key_base` is used as the input secret to the application's key generator, which is used to encrypt cookies. Rage will fall back to the `SECRET_KEY_BASE` environment variable if this is not set.
#
# • _config.fallback_secret_key_base_
#
# > Defines one or several old secrets that need to be rotated. Can accept a single key or an array of keys. Rage will fall back to the `FALLBACK_SECRET_KEY_BASE` environment variable if this is not set.
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
# > Specifies the number of server processes to run. Defaults to 1 in development and to the number of available CPU cores in other environments.
#
# • _config.server.timeout_
#
# > Specifies connection timeout.
#
# # Static file server
#
# • _config.public_file_server.enabled_
#
# > Configures whether Rage should serve static files from the public directory. Defaults to `false`.
#
# # Cable Configuration
#
# • _config.cable.protocol_
#
# > Specifies the protocol the server will use. The only value currently supported is `Rage::Cable::Protocols::ActioncableV1Json`. The client application will need to use [@rails/actioncable](https://www.npmjs.com/package/@rails/actioncable) to talk to the server.
#
# • _config.cable.allowed_request_origins_
#
# > Restricts the server to only accept requests from specified origins. The origins can be instances of strings or regular expressions, against which a check for the match will be performed.
#
# • _config.cable.disable_request_forgery_protection_
#
# > Allows requests from any origin.
#
# # OpenAPI Configuration
# • _config.openapi.tag_resolver_
#
# > Specifies the proc to build tags for API operations. The proc accepts the controller class, the symbol name of the action, and the default tag built by Rage.
#
# > ```ruby
# config.openapi.tag_resolver = proc do |controller, action, default_tag|
#    # ...
# end
# > ```
#
# # Transient Settings
#
# The settings described in this section should be configured using **environment variables** and are either temporary or will become the default in the future.
#
# • _RAGE_DISABLE_IO_WRITE_
#
# > Disables the `io_write` hook to fix the ["zero-length iov"](https://bugs.ruby-lang.org/issues/19640) error on Ruby < 3.3.
#
# • _RAGE_DISABLE_AR_POOL_PATCH_
#
# > Disables the `ActiveRecord::ConnectionPool` patch and makes Rage use the original ActiveRecord implementation.
#
# • _RAGE_DISABLE_AR_WEAK_CONNECTIONS_
#
# > Instructs Rage to not reuse Active Record connections between different fibers.
#
class Rage::Configuration
  attr_accessor :logger
  attr_reader :log_formatter, :log_level
  attr_writer :secret_key_base, :fallback_secret_key_base

  # used in DSL
  def config = self

  def log_formatter=(formatter)
    raise ArgumentError, "Custom log formatter should respond to `#call`" unless formatter.respond_to?(:call)
    @log_formatter = formatter
  end

  def log_level=(level)
    @log_level = level.is_a?(Symbol) ? Logger.const_get(level.to_s.upcase) : level
  end

  def secret_key_base
    @secret_key_base || ENV["SECRET_KEY_BASE"]
  end

  def fallback_secret_key_base
    Array(@fallback_secret_key_base || ENV["FALLBACK_SECRET_KEY_BASE"])
  end

  def server
    @server ||= Server.new
  end

  def middleware
    @middleware ||= Middleware.new
  end

  def cable
    @cable ||= Cable.new
  end

  def public_file_server
    @public_file_server ||= PublicFileServer.new
  end

  def openapi
    @openapi ||= OpenAPI.new
  end

  def internal
    @internal ||= Internal.new
  end

  class Server
    attr_accessor :port, :workers_count, :timeout, :max_clients
    attr_reader :threads_count

    def initialize
      @threads_count = 1
      @workers_count = Rage.env.development? ? 1 : -1
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

    def include?(middleware)
      !!find_middleware_index(middleware) rescue false
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

  class Cable
    attr_accessor :protocol, :allowed_request_origins, :disable_request_forgery_protection

    def initialize
      @protocol = Rage::Cable::Protocols::ActioncableV1Json
      @allowed_request_origins = if Rage.env.development? || Rage.env.test?
        /localhost/
      end
    end

    # @private
    def middlewares
      @middlewares ||= begin
        origin_middleware = if @disable_request_forgery_protection
          []
        else
          [[Rage::OriginValidator, Array(@allowed_request_origins), nil]]
        end

        origin_middleware + Rage.config.middleware.middlewares.reject do |middleware, _, _|
          middleware == Rage::FiberWrapper
        end
      end
    end

    def config
      @config ||= begin
        config_file = Rage.root.join("config/cable.yml")

        if config_file.exist?
          yaml = ERB.new(config_file.read).result
          YAML.safe_load(yaml, aliases: true, symbolize_names: true)[Rage.env.to_sym] || {}
        else
          {}
        end
      end
    end

    def adapter_config
      config.except(:adapter)
    end

    def adapter
      case config[:adapter]
      when "redis"
        Rage::Cable::Adapters::Redis.new(adapter_config)
      end
    end
  end

  class PublicFileServer
    attr_accessor :enabled
  end

  class OpenAPI
    attr_accessor :tag_resolver
  end

  # @private
  class Internal
    attr_accessor :rails_mode

    def patch_ar_pool?
      !ENV["RAGE_DISABLE_AR_POOL_PATCH"] && !Rage.env.test?
    end

    # whether we should manually release AR connections;
    # AR 7.2+ uses `with_connection` internaly, so we only need to do this for older versions;
    def should_manually_release_ar_connections?
      defined?(ActiveRecord) && ActiveRecord.version < Gem::Version.create("7.2.0")
    end

    # whether we should manually reconnect closed AR connections;
    # AR 7.1+ does this automatically while executing the query;
    def should_manually_restore_ar_connections?
      defined?(ActiveRecord) && ActiveRecord.version < Gem::Version.create("7.1.0")
    end

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

# frozen_string_literal: true

require "yaml"
require "erb"

##
# Configuration class for Rage framework.
#
# Use {Rage.configure Rage.configure} to access and modify the configuration.
#
# **Example:**
# ```ruby
# Rage.configure do
#   config.log_level = :warn
#   config.server.port = 8080
# end
# ```
#
# ## Transient Settings
#
# The settings described in this section should be configured using **environment variables** and are either temporary or will become the default in the future.
#
# - _RAGE_DISABLE_IO_WRITE_ - disables the `io_write` hook to fix the ["zero-length iov"](https://bugs.ruby-lang.org/issues/19640) error on Ruby < 3.3.
# - _RAGE_DISABLE_AR_POOL_PATCH_ - disables the `ActiveRecord::ConnectionPool` patch and makes Rage use the original ActiveRecord implementation.
# - _RAGE_DISABLE_AR_WEAK_CONNECTIONS_ - instructs Rage to not reuse Active Record connections between different fibers. Only applies to Active Record < 7.2.
#
class Rage::Configuration
  # @private
  include Hooks

  # @private
  # used in DSL
  def config = self

  # @!group General Configuration

  # Returns the logger used by Rage.
  # @return [Rage::Logger, nil]
  def logger
    @logger
  end

  # Set the logger used by Rage.
  # Accepts a logger object that implements the `#debug`, `#info`, `#warn`, `#error`, `#fatal`, and `#unknown` methods, or `nil`. If set to `nil`, logging will be disabled.
  # `Rage.logger` always returns an instance of {Rage::Logger Rage::Logger}, but if you provide a custom object, it will be used internally by `Rage.logger`.
  #
  # @overload logger=(logger)
  #   Set a standard logger
  #   @param logger [#debug, #info, #warn, #error, #fatal, #unknown]
  #   @example
  #     config.logger = Rage::Logger.new(STDOUT)
  # @overload logger=(callable)
  #   Set an external logger. This allows you to send Rage's raw structured logging data directly to external observability platforms without serializing it to text first.
  #
  #   The external logger receives pre-parsed structured data (severity, tags, context) rather than formatted strings. This differs from `config.log_formatter` in that formatters control how logs are formatted (text vs JSON), while the external logger controls where logs are sent and how they integrate with external platforms.
  #   @param callable [ExternalLoggerInterface]
  #   @example
  #     config.logger = proc do |severity:, tags:, context:, message:, request_info:|
  #       # Custom logging logic here
  #     end
  # @overload logger=(nil)
  #  Disable logging
  #  @example
  #    config.logger = nil
  def logger=(logger)
    @logger = if logger.nil? || logger.is_a?(Rage::Logger)
      logger
    elsif Rage::Logger::METHODS_MAP.keys.all? { |method| logger.respond_to?(method) }
      Rage::Logger.new(Rage::Logger::External::Static[logger])
    elsif logger.respond_to?(:call)
      Rage::Logger.new(Rage::Logger::External::Dynamic[logger])
    else
      raise ArgumentError, "Invalid logger: must be an instance of `Rage::Logger`, respond to `#call`, or implement all standard Ruby Logger methods (`#debug`, `#info`, `#warn`, `#error`, `#fatal`, `#unknown`)"
    end
  end

  # Returns the log formatter used by Rage.
  # @return [#call, nil]
  def log_formatter
    @log_formatter
  end

  # Set the log formatter used by Rage.
  # Built in options include {Rage::TextFormatter Rage::TextFormatter} and {Rage::JSONFormatter Rage::JSONFormatter}.
  #
  # @param formatter [#call] a callable object that formats log messages
  # @example
  #   config.log_formatter = proc do |severity, datetime, progname, msg|
  #     "[#{datetime}] #{severity} -- #{progname}: #{msg}\n"
  #   end
  def log_formatter=(formatter)
    raise ArgumentError, "Custom log formatter should respond to `#call`" unless formatter.respond_to?(:call)
    @log_formatter = formatter
  end

  # Returns the log level used by Rage.
  # @return [Integer, nil]
  def log_level
    @log_level
  end

  # Set the log level used by Rage.
  # @param level [:debug, :info, :warn, :error, :fatal, :unknown, Integer] the log level
  # @example
  #   config.log_level = :info
  def log_level=(level)
    @log_level = level.is_a?(Symbol) ? Logger.const_get(level.to_s.upcase) : level
  end

  # The secret key base is used as the input secret to the application's key generator, which is used to encrypt cookies. Rage will fall back to the `SECRET_KEY_BASE` environment variable if this is not set.
  # @param key [String] the secret key base
  def secret_key_base=(key)
    @secret_key_base = key
  end

  # Returns the secret key base used for encrypting cookies.
  # @return [String, nil]
  def secret_key_base
    @secret_key_base || ENV["SECRET_KEY_BASE"]
  end

  # Set one or several old secrets that need to be rotated. Can accept a single key or an array of keys. Rage will fall back to the `FALLBACK_SECRET_KEY_BASE` environment variable if this is not set.
  # @param key [String, Array<String>] the fallback secret key base(s)
  def fallback_secret_key_base=(key)
    @fallback_secret_key_base = key
  end

  # Returns the fallback secret key base(s) used for decrypting cookies encrypted with old secrets.
  # @return [Array<String>]
  def fallback_secret_key_base
    Array(@fallback_secret_key_base || ENV["FALLBACK_SECRET_KEY_BASE"])
  end

  # Schedule a block of code to run after Rage has finished loading the application code. Use this to reference application-level constants during the initialization process.
  # @example
  #   Rage.config.after_initialize do
  #     SUPER_USER = User.find_by!(super: true)
  #   end
  def after_initialize(&block)
    push_hook(block, :after_initialize)
  end
  # @!endgroup

  # @!group Middleware Configuration
  # Allows configuring the middleware stack used by Rage.
  # @return [Rage::Configuration::Middleware]
  def middleware
    @middleware ||= Middleware.new
  end
  # @!endgroup

  # @!group Server Configuration
  # Allows configuring the built-in Rage server.
  # @return [Rage::Configuration::Server]
  def server
    @server ||= Server.new
  end
  # @!endgroup

  # @!group Static File Server
  # Allows configuring the static file server used by Rage.
  # @return [Rage::Configuration::PublicFileServer]
  def public_file_server
    @public_file_server ||= PublicFileServer.new
  end
  # @!endgroup

  # @!group Cable Configuration
  # Allows configuring Cable settings.
  # @return [Rage::Configuration::Cable]
  def cable
    @cable ||= Cable.new
  end
  # @!endgroup

  # @!group OpenAPI Configuration
  # Allows configuring OpenAPI settings.
  # @return [Rage::Configuration::OpenAPI]
  def openapi
    @openapi ||= OpenAPI.new
  end
  # @!endgroup

  # @!group Deferred Configuration
  # Allows configuring Deferred settings.
  # @return [Rage::Configuration::Deferred]
  def deferred
    @deferred ||= Deferred.new
  end
  # @!endgroup

  # @!group Logging Context and Tags Configuration
  # Allows configuring custom log context objects that will be included in every log entry.
  # @return [Rage::Configuration::LogContext]
  def log_context
    @log_context ||= LogContext.new
  end

  # Allows configuring custom log tags that will be included in every log entry.
  # @return [Rage::Configuration::LogTags]
  def log_tags
    @log_tags ||= LogTags.new
  end
  # @!endgroup

  # @!group Telemetry Configuration
  # Allows configuring telemetry settings.
  # @return [Rage::Configuration::Telemetry]
  def telemetry
    @telemetry ||= Telemetry.new
  end
  # @!endgroup

  # @!group Session Configuration
  # Allows configuring session settings.
  # @return [Rage::Configuration::Session]
  def session
    @session ||= Session.new
  end

  # @private
  def internal
    @internal ||= Internal.new
  end

  # @private
  def run_after_initialize!
    run_hooks_for!(:after_initialize, self)
  end

  class LogContext
    # @private
    def initialize
      @objects = []
    end

    # @private
    def objects
      @objects.dup
    end

    # Add a new custom log context object. Each context object is evaluated independently and the results are merged into the final log entry.
    # @overload <<(hash)
    #   Add a static log context entry.
    #   @param hash [Hash] a hash representing the log context
    #   @example
    #     Rage.configure do
    #       config.log_context << { version: ENV["APP_VERSION"] }
    #     end
    # @overload <<(callable)
    #   Add a dynamic log context entry. Dynamic context entries are executed on every log call to capture dynamic state like changing span IDs during request processing.
    #   @param callable [#call] a callable object that returns a hash representing the log context or nil
    #   @example
    #     Rage.configure do
    #       config.log_context << proc { { trace_id: MyObservabilitySDK.trace_id } if MyObservabilitySDK.active? }
    #     end
    #   @note Exceptions from dynamic context callables will cause the entire request to fail. Make sure to handle exceptions inside the callable if necessary.
    def <<(block_or_hash)
      validate_input!(block_or_hash)
      @objects << block_or_hash
      @objects.tap(&:flatten!).tap(&:uniq!)

      self
    end

    alias_method :push, :<<

    # Remove a custom log context object.
    # @param block_or_hash [Hash, #call] the context object to remove
    # @example
    #   Rage.configure do
    #     config.log_context.delete(MyObservabilitySDK::LOG_CONTEXT)
    #   end
    def delete(block_or_hash)
      @objects.delete(block_or_hash)
    end

    private

    def validate_input!(obj)
      if obj.is_a?(Array)
        obj.each { |item| validate_input!(item) }
      elsif !obj.is_a?(Hash) && !obj.respond_to?(:call)
        raise ArgumentError, "custom log context has to be a hash, an array of hashes, or respond to `#call`"
      end
    end
  end

  class LogTags < LogContext
    # @!method <<(block_or_string)
    #   Add a new custom log tag. Each tag is evaluated independently and the results are merged into the final log entry.
    #   @overload <<(string)
    #     Add a static log tag.
    #     @param string [String] the log tag
    #     @example
    #       Rage.configure do
    #         config.log_tags << Rage.env
    #       end
    #   @overload <<(callable)
    #     Add a dynamic log tag. Dynamic tags are executed on every log call.
    #     @param callable [#call] a callable object that returns a string representing the log tag, an array of log tags, or nil
    #     @example
    #       Rage.configure do
    #         config.log_tags << proc { Current.tenant.slug }
    #       end
    #     @note Exceptions from dynamic tag callables will cause the entire request to fail. Make sure to handle exceptions inside the callable if necessary.

    # @!method delete(block_or_string)
    #   Remove a custom log tag object.
    #   @param block_or_string [String, #call] the tag object to remove
    #   @example
    #     Rage.configure do
    #       config.log_tags.delete(MyObservabilitySDK::LOG_TAGS)
    #     end

    # @private
    private

    def validate_input!(obj)
      if obj.is_a?(Array)
        obj.each { |item| validate_input!(item) }
      elsif !obj.respond_to?(:to_str) && !obj.respond_to?(:call)
        raise ArgumentError, "custom log tag has to be a string, an array of strings, or respond to `#call`"
      end
    end
  end

  class Server
    # @!attribute port
    #   Specify the port the server will listen on.
    #   @return [Integer]
    #   @example Change the default port
    #     Rage.configure do
    #       config.server.port = 3001
    #     end
    #
    # @!attribute workers_count
    #   Specify the number of worker processes to spawn. Use `-1` to spawn one worker per CPU core.
    #   @return [Integer]
    #   @example Change the number of worker processes
    #     Rage.configure do
    #       config.server.workers_count = 4
    #     end
    #
    # @!attribute timeout
    #   Specify the connection timeout in seconds.
    #   @return [Integer]
    #   @example Change the connection timeout
    #     Rage.configure do
    #       config.server.timeout = 30
    #     end
    #
    # @!attribute max_clients
    #   Limit the number of simultaneous connections the server can accept. Defaults to the maximum number of open files.
    #   @return [Integer]
    #
    #   @note Decreasing this number is almost never a good idea. Depending on your application specifics, you are encouraged to use other methods to limit the number of concurrent connections:
    #
    #     - If your application is exposed to the public, you may want to use a cloud rate limiter, like {https://developers.cloudflare.com/waf Cloudflare WAF} or {https://docs.fastly.com/en/ngwaf Fastly WAF}.
    #     - Otherwise, consider using tools like {https://github.com/rack/rack-attack Rack::Attack} or {https://github.com/mperham/connection_pool connection_pool}.
    #   @example Limit the amount of connections your application can accept
    #     Rage.configure do
    #       config.middleware.use Rack::Attack
    #       Rack::Attack.throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    #         req.ip
    #       end
    #     end
    #   @example Limit the amount of connections to a specific resource
    #     HTTP = ConnectionPool.new(size: 5, timeout: 5) { Net::HTTP }
    #     HTTP.with do |conn|
    #       conn.get("/my-resource")
    #     end
    attr_accessor :port, :workers_count, :timeout, :max_clients

    # @private
    attr_reader :threads_count

    # @private
    def initialize
      @threads_count = 1
      @workers_count = Rage.env.development? ? 1 : -1
      @port = 3000
    end
  end

  class MiddlewareRegistry
    # @private
    attr_reader :objects

    # @private
    def initialize
      @objects = []
    end

    # Add a new middleware to the end of the stack.
    # @note This is the recommended way of adding a middleware.
    # @param new_middleware [Class] the middleware class
    # @param args [Array] arguments passed to the middleware initializer
    # @param block [Proc] an optional block passed to the middleware initializer
    # @example
    #   Rage.configure do
    #     config.middleware.use Rack::Cors do
    #       allow do
    #         origins "*"
    #         resource "*", headers: :any
    #       end
    #     end
    #   end
    def use(new_middleware, *args, &block)
      validate!(-1, new_middleware)
      @objects.insert(-1, [new_middleware, args, block])
    end

    # Insert a new middleware before an existing middleware in the stack.
    # @note Rage always uses the `Rage::FiberWrapper` middleware, which wraps every request in a separate fiber. Make sure to always have this middleware in the top of the stack. Placing other middlewares in front may lead to undefined behavior.
    # @param existing_middleware [Class, Integer] the existing middleware class or its index in the stack
    # @param new_middleware [Class] the new middleware class
    # @param args [Array] arguments passed to the middleware initializer
    # @param block [Proc] an optional block passed to the middleware initializer
    # @example
    #   Rage.configure do
    #     config.middleware.insert_before Rack::Runtime, Rack::Cors do
    #       allow do
    #         origins "*"
    #         resource "*", headers: :any
    #       end
    #     end
    #   end
    def insert_before(existing_middleware, new_middleware, *args, &block)
      index = find_object_index(existing_middleware)
      validate!(index, new_middleware)
      @objects.insert(index, [new_middleware, args, block])
    end

    # Insert a new middleware after an existing middleware in the stack.
    # @param existing_middleware [Class, Integer] the existing middleware class or its index in the stack
    # @param new_middleware [Class] the new middleware class
    # @param args [Array] arguments passed to the middleware initializer
    # @param block [Proc] an optional block passed to the middleware initializer
    # @example
    #   Rage.configure do
    #     config.middleware.insert_after Rack::Runtime, Rack::Cors do
    #       allow do
    #         origins "*"
    #         resource "*", headers: :any
    #       end
    #     end
    #   end
    def insert_after(existing_middleware, new_middleware, *args, &block)
      index = find_object_index(existing_middleware) + 1
      index = 0 if @objects.empty?
      validate!(index, new_middleware)
      @objects.insert(index, [new_middleware, args, block])
    end

    # Check if a middleware is included in the stack.
    # @param middleware [Class] the middleware class
    # @return [Boolean]
    def include?(middleware)
      @objects.any? { |o, _, _| o == middleware }
    end

    # Delete a middleware from the stack.
    # @param middleware [Class] the middleware class
    # @example
    #   Rage.configure do
    #     config.middleware.delete Rack::Cors
    #   end
    def delete(middleware)
      @objects.reject! { |o, _, _| o == middleware }
    end

    private

    def find_object_index(object)
      if object.is_a?(Integer)
        if @objects[object] || object == 0
          object
        else
          raise ArgumentError, "Could not find middleware at index #{object}"
        end
      else
        index = @objects.index { |o, _, _| o == object }
        raise ArgumentError, "Could not find `#{object}` in the middleware registry" unless index
        index
      end
    end

    def validate!(_, _)
    end
  end

  # See {Rage::Configuration::MiddlewareRegistry Rage::Configuration::MiddlewareRegistry} for details on available methods.
  class Middleware < MiddlewareRegistry
    # @private
    alias_method :middlewares, :objects

    # @private
    def initialize
      super
      @objects = [[Rage::FiberWrapper]]
    end

    private

    def validate!(index, middleware)
      if index == 0 && @objects[0][0] == Rage::FiberWrapper
        puts "WARNING: inserting the `#{middleware}` middleware before `Rage::FiberWrapper` may cause undefined behavior."
      end
    end
  end

  class Cable
    # @!attribute allowed_request_origins
    #   Restrict the server to only accept requests from specified origins. The origins can be strings or regular expressions. Defaults to `/localhost/` in development and test environments.
    #   @return [Array<Regexp>, Regexp, Array<String>, String, nil]
    #   @example
    #     Rage.configure do
    #       config.cable.allowed_request_origins = [/example\.com/, "myapp.com"]
    #     end
    #
    # @!attribute disable_request_forgery_protection
    #   Disable request forgery protection for WebSocket connections to allow requests from any origin.
    #   @return [Boolean]
    #   @example
    #     Rage.configure do
    #       config.cable.disable_request_forgery_protection = true
    #     end
    attr_accessor :allowed_request_origins, :disable_request_forgery_protection

    # @private
    def initialize
      @protocol = Rage::Cable::Protocols::ActioncableV1Json
      @allowed_request_origins = if Rage.env.development? || Rage.env.test?
        /localhost/
      end
    end

    # Returns the protocol the server will use.
    # @return [Class] the protocol class
    def protocol
      @protocol
    end

    # Specify the protocol the server will use. Supported values include {Rage::Cable::Protocols::ActioncableV1Json :actioncable_v1_json} and {Rage::Cable::Protocols::RawWebSocketJson :raw_websocket_json}. Defaults to {Rage::Cable::Protocols::ActioncableV1Json :actioncable_v1_json}.
    # @param protocol [:actioncable_v1_json, :raw_websocket_json] the protocol symbol
    # @example Use the built-in ActionCable V1 JSON protocol
    #   Rage.configure do
    #     config.cable.protocol = :actioncable_v1_json
    #   end
    # @example Use the built-in Raw WebSocket JSON protocol
    #   Rage.configure do
    #     config.cable.protocol = :raw_websocket_json
    #   end
    def protocol=(protocol)
      @protocol = case protocol
      when Class
        protocol
      when :actioncable_v1_json
        Rage::Cable::Protocols::ActioncableV1Json
      when :raw_websocket_json
        Rage::Cable::Protocols::RawWebSocketJson
      else
        raise ArgumentError, "Unknown protocol. Supported values are `:actioncable_v1_json` and `:raw_websocket_json`."
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

    # @private
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

    # @private
    def adapter_config
      config.except(:adapter)
    end

    # @private
    def adapter
      case config[:adapter]
      when "redis"
        Rage::Cable::Adapters::Redis.new(adapter_config)
      end
    end
  end

  class PublicFileServer
    # @!attribute enabled
    #  Configure whether Rage should serve static files from the `public` directory. Defaults to `false`.
    #  @return [Boolean] whether the static file server is enabled
    #  @example
    #    Rage.configure do
    #      config.public_file_server.enabled = true
    #    end
    attr_accessor :enabled
  end

  class OpenAPI
    # Specify the rules to customize how OpenAPI tags are generated for API operations.
    # The method accepts a callable object that receives the controller class, the action name (as a symbol), and the original tag generated by Rage.
    # The callable should return a string or an array of strings representing the tags to use for the API operation.
    # This enables grouping endpoints in the OpenAPI documentation according to your application's needs.
    # @param tag_resolver [#call] a callable object that resolves OpenAPI tags
    # @example
    #   Rage.configure do
    #     config.openapi.tag_resolver = proc do |controller_class, action_name, default_tag|
    #       if controller_class.name.start_with?("Admin::")
    #         [default_tag, "Admin"]
    #       else
    #         [default_tag, "Public"]
    #       end
    #     end
    #   end
    def tag_resolver=(tag_resolver)
      unless tag_resolver.respond_to?(:call)
        raise ArgumentError, "Custom tag resolver should respond to `#call`"
      end

      @tag_resolver = tag_resolver
    end

    # Returns the OpenAPI tag resolver used by Rage.
    # @return [#call, nil]
    def tag_resolver
      @tag_resolver
    end
  end

  class Deferred
    # @private
    def initialize
      @configured = false
    end

    # Returns the backend instance used by `Rage::Deferred`.
    def backend
      unless @backend_class
        @backend_class = Rage::Deferred::Backends::Disk
        @backend_options = parse_disk_backend_options({})
      end

      @backend_class.new(**@backend_options)
    end

    # Specify the backend used to persist deferred tasks. Supported values are `:disk`, which uses disk storage, or `nil`, which disables persistence of deferred tasks.
    # @overload backend=(disk, options = {})
    #   Use the disk backend.
    #   @param options [Hash] additional backend options
    #   @option options [Pathname, String] :path the directory where deferred tasks will be stored. Defaults to `storage/`
    #   @option options [String] :prefix the prefix used for deferred task files. Defaults to `deferred-`
    #   @option options [Integer] :fsync_frequency the frequency of `fsync` calls in seconds. Defaults to `0.5`
    #   @example Use the disk backend with default options
    #     Rage.configure do
    #       config.deferred.backend = :disk
    #     end
    #   @example Use the disk backend with custom options
    #     Rage.configure do
    #       config.deferred.backend = :disk, path: "my_storage", fsync_frequency: 1000
    #     end
    # @overload backend=(nil)
    #   Disable persistence of deferred tasks.
    #   @example
    #     Rage.configure do
    #       config.deferred.backend = nil
    #     end
    def backend=(config)
      @configured = true

      backend_id, opts = if config.is_a?(Array)
        [config[0], config[1]]
      else
        [config, {}]
      end

      @backend_class = case backend_id
      when :disk
        @backend_options = parse_disk_backend_options(opts)
        Rage::Deferred::Backends::Disk
      when nil
        Rage::Deferred::Backends::Nil
      else
        raise ArgumentError, "unsupported backend value; supported keys are `:disk` and `nil`"
      end
    end

    class Backpressure
      attr_reader :high_water_mark, :low_water_mark, :timeout, :sleep_interval, :timeout_iterations

      # @private
      def initialize(high_water_mark = nil, low_water_mark = nil, timeout = nil)
        @high_water_mark = high_water_mark || 1_000
        @low_water_mark = low_water_mark || (@high_water_mark * 0.8).round

        @timeout = timeout || 2
        @sleep_interval = 0.05
        @timeout_iterations = (@timeout / @sleep_interval).round
      end
    end

    # Returns the backpressure configuration used by `Rage::Deferred`.
    # @return [Backpressure, nil]
    def backpressure
      @backpressure
    end

    # Configure backpressure settings for `Rage::Deferred`. Backpressure is used to limit the number of pending tasks in the queue and is disabled by default.
    #
    # @overload backpressure=(true)
    #   Enable backpressure with default settings.
    #   @example
    #     Rage.configure do
    #       config.deferred.backpressure = true
    #     end
    #
    # @overload backpressure=(false)
    #   Disable backpressure.
    #   @example
    #     Rage.configure do
    #       config.deferred.backpressure = false
    #     end
    #
    # @overload backpressure=(config)
    #   Enable backpressure with custom settings.
    #   @param config [Hash] backpressure configuration
    #   @option config [Integer] :high_water_mark the maximum number of deferred tasks allowed in the queue before applying backpressure. Defaults to `1000`.
    #   @option config [Integer] :low_water_mark the minimum number of deferred tasks in the queue at which backpressure is lifted. Defaults to `80%` of `:high_water_mark`.
    #   @option config [Integer] :timeout the maximum time in seconds to wait for the queue size to drop below `:low_water_mark` before raising the {Rage::Deferred::PushTimeout Rage::Deferred::PushTimeout} exception. Defaults to 2 seconds.
    #   @example
    #     Rage.configure do
    #       config.deferred.backpressure = { high_water_mark: 2000, low_water_mark: 1500, timeout: 5 }
    #     end
    def backpressure=(config)
      @configured = true

      if config == true
        @backpressure = Backpressure.new
        return
      elsif config == false
        @backpressure = nil
        return
      end

      if config.except(:high_water_mark, :low_water_mark, :timeout).any?
        raise ArgumentError, "unsupported backpressure options; supported keys are `:high_water_mark`, `:low_water_mark`, `:timeout`"
      end

      high_water_mark, low_water_mark, timeout = config.values_at(:high_water_mark, :low_water_mark, :timeout)
      @backpressure = Backpressure.new(high_water_mark, low_water_mark, timeout)
    end

    # Allows configuring middleware used by `Rage::Deferred`. See {MiddlewareRegistry} for details on available methods.
    # @example
    #   Rage.configure do
    #     config.deferred.enqueue_middleware.use MyEnqueueMiddleware
    #     config.deferred.enqueue_middleware.insert_before MyEnqueueMiddleware, MyLoggingMiddleware
    #   end
    class Middleware < Rage::Configuration::MiddlewareRegistry
      private

      def validate!(_, middleware)
        unless middleware.is_a?(Class)
          raise ArgumentError, "Deferred middleware has to be a class"
        end

        unless middleware.method_defined?(:call)
          raise ArgumentError, "Deferred middleware has to implement the `#call` method"
        end
      end
    end

    # Configure enqueue middleware used by `Rage::Deferred`.
    # See {EnqueueMiddlewareInterface} for details on the arguments passed to the middleware.
    # @return [Rage::Configuration::Deferred::Middleware]
    # @example
    #   Rage.configure do
    #     config.deferred.enqueue_middleware.use MyCustomMiddleware
    #   end
    def enqueue_middleware
      @enqueue_middleware ||= Middleware.new
    end

    # Configure perform middleware used by `Rage::Deferred`.
    # See {PerformMiddlewareInterface} for details on the arguments passed to the middleware.
    # @return [Rage::Configuration::Deferred::Middleware]
    # @example
    #   Rage.configure do
    #     config.deferred.perform_middleware.use MyCustomMiddleware
    #   end
    def perform_middleware
      @perform_middleware ||= Middleware.new
    end

    # @private
    def default_disk_storage_path
      Pathname.new("storage")
    end

    # @private
    def default_disk_storage_prefix
      "deferred-"
    end

    # @private
    def has_default_disk_storage?
      default_disk_storage_path.glob("#{default_disk_storage_prefix}*").any?
    end

    # @private
    def configured?
      @configured
    end

    private

    def parse_disk_backend_options(opts)
      if opts.except(:path, :prefix, :fsync_frequency).any?
        raise ArgumentError, "unsupported backend options; supported values are `:path`, `:prefix`, `:fsync_frequency`"
      end

      parsed_options = {}

      parsed_options[:path] = if opts[:path]
        opts[:path].is_a?(Pathname) ? opts[:path] : Pathname.new(opts[:path])
      else
        default_disk_storage_path
      end

      parsed_options[:prefix] = if opts[:prefix]
        opts[:prefix].end_with?("-") ? opts[:prefix] : "#{opts[:prefix]}-"
      else
        default_disk_storage_prefix
      end

      parsed_options[:fsync_frequency] = if opts[:fsync_frequency]
        (opts[:fsync_frequency].to_i * 1_000).round
      else
        500
      end

      parsed_options
    end
  end

  # The class allows configuring telemetry handlers. See {MiddlewareRegistry} for details on available methods.
  # @example
  #   Rage.configure do
  #     config.telemetry.use MyTelemetryHandler.new
  #   end
  # @see Rage::Configuration::MiddlewareRegistry
  # @see Rage::Telemetry
  class Telemetry < MiddlewareRegistry
    # @private
    # @return [Hash{String => Array<Rage::Telemetry::HandlerRef>}] a map of span IDs to handler references
    def handlers_map
      @objects.map(&:first).each_with_object({}) do |handler, memo|
        handlers_map = handler.is_a?(Class) ? handler.handlers_map : handler.class.handlers_map

        handlers_map.each do |span_id, handler_methods|
          handler_refs = handler_methods.map do |handler_method|
            Rage::Telemetry::HandlerRef[handler, handler_method]
          end

          if memo[span_id]
            memo[span_id] += handler_refs
          else
            memo[span_id] = handler_refs
          end
        end
      end
    end

    private

    def validate!(_, handler)
      is_handler = if handler.is_a?(Class)
        handler.ancestors.include?(Rage::Telemetry::Handler)
      else
        handler.is_a?(Rage::Telemetry::Handler)
      end

      unless is_handler
        raise ArgumentError, "Cannot add `#{handler}` as a telemetry handler; should inherit `Rage::Telemetry::Handler`"
      end

      handlers_map = if handler.is_a?(Class)
        handler.handlers_map
      else
        handler.class.handlers_map
      end

      unless handlers_map&.any?
        raise ArgumentError, "Telemetry handler `#{handler}` does not define any handlers"
      end

      handlers_map.values.reduce(&:+).each do |handler_method|
        unless handler.respond_to?(handler_method)
          raise ArgumentError, "Telemetry handler `#{handler}` does not implement the `#{handler_method}` handler method"
        end
      end
    end
  end

  class Session
    # @!attribute key
    #   Specify the name of the session cookie.
    #   @return [String]
    #   @example Change the session cookie name
    #     Rage.configure do
    #       config.session.key = "_myapp_session"
    #     end
    attr_accessor :key
  end

  # @private
  class Internal
    attr_accessor :rails_mode

    def initialized!
      @initialized = true
    end

    def initialized?
      !!@initialized
    end

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

    if @log_formatter && @logger.external_logger.is_a?(Rage::Logger::External::Dynamic)
      puts "WARNING: changing the log formatter via `config.log_formatter=` has no effect when using a custom external logger."
    end

    if @log_context
      Rage.__log_processor.add_custom_context(@log_context.objects)
      @logger.dynamic_context = Rage.__log_processor.dynamic_context
    end

    if @log_tags
      Rage.__log_processor.add_custom_tags(@log_tags.objects)
      @logger.dynamic_tags = Rage.__log_processor.dynamic_tags
    end

    if defined?(::Rack::Events) && middleware.include?(::Rack::Events)
      middleware.delete(Rage::BodyFinalizer)
      middleware.insert_before(::Rack::Events, Rage::BodyFinalizer)
    end
  end
end

# @!parse [ruby]
#   # @note This class does not exist at runtime and is used for documentation purposes only. Do not inherit external loggers from it.
#   class ExternalLoggerInterface
#     # Called whenever a log entry is created.
#     #
#     # Rage automatically detects which parameters your external logger's `#call` method accepts, and only passes those parameters. You can omit any of the described parameters in your implementation.
#     #
#     # @param severity [:debug, :info, :warn, :error, :fatal, :unknown] the log severity
#     # @param tags [Array] the log tags submitted via {Rage::Logger#tagged Rage::Logger#tagged}. The first tag is always the request ID
#     # @param context [Hash] the log context submitted via {Rage::Logger#with_context Rage::Logger#with_context}
#     # @param message [String, nil] the log message. For request logs generated by Rage, this is always `nil`
#     # @param request_info [Hash, nil] request-specific information. The value is `nil` for non-request logs; for request logs, contains the following keys:
#     # @option request_info [Hash] :env the Rack env object
#     # @option request_info [Hash] :params the request parameters
#     # @option request_info [Array] :response the Rack response object
#     # @option request_info [Float] :duration the duration of the request in milliseconds
#     # @example
#     #   Rage.configure do
#     #     config.logger = proc do |severity:, tags:, context:, message:, request_info:|
#     #       data = context.merge(tags:)
#     #
#     #       if request_info
#     #         data[:path] = request_info[:env]["PATH_INFO"]
#     #         MyLoggingSDK.info("Request completed", data)
#     #       else
#     #         MyLoggingSDK.public_send(severity, message, data)
#     #       end
#     #     end
#     #   end
#     def call(severity:, tags:, context:, message:, request_info:)
#     end
#   end

# @!parse [ruby]
#   # @note This class does not exist at runtime and is used for documentation purposes only. Do not inherit your middleware classes from it.
#   class EnqueueMiddlewareInterface
#     # Called whenever a deferred task is enqueued.
#     #
#     # The middleware is expected to call `yield` to pass control to the next middleware in the stack. If the middleware does not call `yield`, the task will not be enqueued.
#     #
#     # Rage automatically detects which parameters your middleware's `#call` method accepts, and only passes those parameters. You can omit any of the described parameters in your implementation.
#     #
#     # @param task_class [Class] the deferred task class
#     # @param delay [Integer, nil] the delay in seconds before the task is executed
#     # @param delay_until [Time, Integer, nil] the time at which the task should be executed
#     # @param phase [:enqueue] the middleware phase. Useful for middlewares that are shared between enqueue and perform phases
#     # @param args [Array] the positional arguments passed to the task
#     # @param kwargs [Hash] the keyword arguments passed to the task
#     # @param context [Hash] the context is serialized together with the task and allows passing data between middlewares without exposing it to the task itself
#     # @example
#     #   class EncryptArgumentsMiddleware
#     #     def call(args:, kwargs:)
#     #       args.map! { |arg| MyEncryptionSDK.encrypt(arg) }
#     #       kwargs.transform_values! { |value| MyEncryptionSDK.encrypt(value) }
#     #
#     #       yield
#     #     end
#     #   end
#     def call(task_class:, delay:, delay_until:, phase:, args:, kwargs:, context:)
#     end
#   end

# @!parse [ruby]
#   # @note This class does not exist at runtime and is used for documentation purposes only. Do not inherit your middleware classes from it.
#   class PerformMiddlewareInterface
#     # Called whenever a deferred task is performed.
#     #
#     # The middleware is expected to call `yield` to pass control to the next middleware in the stack. If the middleware does not call `yield`, the task will not be performed.
#     #
#     # Rage automatically detects which parameters your middleware's `#call` method accepts, and only passes those parameters. You can omit any of the described parameters in your implementation.
#     #
#     # @param task_class [Class] the deferred task class
#     # @param task [Rage::Deferred::Task] the deferred task instance
#     # @param phase [:perform] the middleware phase. Useful for middlewares that are shared between enqueue and perform phases
#     # @param args [Array] the positional arguments passed to the task
#     # @param kwargs [Hash] the keyword arguments passed to the task
#     # @param context [Hash] the context is serialized together with the task and allows passing data between middlewares without exposing it to the task itself
#     # @example
#     #   class DecryptArgumentsMiddleware
#     #     def call(args:, kwargs:)
#     #       args.map! { |arg| MyEncryptionSDK.decrypt(arg) }
#     #       kwargs.transform_values! { |value| MyEncryptionSDK.decrypt(value) }
#     #
#     #       yield
#     #
#     #     rescue
#     #       # Re-encrypt the arguments in case of an error
#     #       args.map! { |arg| MyEncryptionSDK.encrypt(arg) }
#     #       kwargs.transform_values! { |value| MyEncryptionSDK.encrypt(value) }
#     #       raise
#     #     end
#     #   end
#     def call(task_class:, task:, phase:, args:, kwargs:, context:)
#     end
#   end

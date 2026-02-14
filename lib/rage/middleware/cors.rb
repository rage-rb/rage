# frozen_string_literal: true

class Rage::Cors
  # @private
  def initialize(app, *, &)
    @app = app
    instance_eval(&)
  end

  # @private
  def call(env)
    if env["REQUEST_METHOD"] == "OPTIONS"
      return (response = @cors_response)
    end

    response = @app.call(env)
    response[1]["access-control-allow-credentials"] = @allow_credentials if @allow_credentials
    response[1]["access-control-expose-headers"] = @expose_headers if @expose_headers

    response
  ensure
    if !$! && (origin = @cors_check.call(env))
      headers = response[1]
      headers["access-control-allow-origin"] = origin
      if @origins != "*"
        vary = headers["vary"]
        if vary.nil?
          headers["vary"] = "Origin"
        elsif vary != "Origin"
          headers["vary"] += ", Origin"
        end
      end
    end
  end

  # Set CORS rules for the application.
  #
  # @param origins [String, Regexp, "*"] origins allowed to access the application
  # @param methods [Array<Symbol>, "*"] allowed methods when accessing the application
  # @param allow_headers [Array<String>, "*"] indicate which HTTP headers can be used when making the actual request
  # @param expose_headers [Array<String>, "*"] adds the specified headers to the allowlist that JavaScript in browsers is allowed to access
  # @param max_age [Integer] indicate how long the results of a preflight request can be cached
  # @param allow_credentials [Boolean] indicate whether or not the response to the request can be exposed when the `credentials` flag is `true`
  # @example
  #   config.middleware.use Rage::Cors do
  #     allow "localhost:5173", "myhost.com"
  #   end
  # @example
  #   config.middleware.use Rage::Cors do
  #     allow "*",
  #       methods: [:get, :post, :put],
  #       allow_headers: ["x-domain-token"],
  #       expose: ["Some-Custom-Response-Header"],
  #       max_age: 600
  #   end
  # @note The middleware only supports the basic case of allowing one or several origins for the whole application. Use {https://github.com/cyu/rack-cors Rack::Cors} if you are looking to specify more advanced rules.
  def allow(*origins, methods: "*", allow_headers: "*", expose_headers: nil, max_age: nil, allow_credentials: false)
    @allow_headers = Array(allow_headers).join(", ") if allow_headers
    @expose_headers = Array(expose_headers).join(", ") if expose_headers
    @max_age = max_age.to_s if max_age
    @allow_credentials = "true" if allow_credentials

    @default_methods = %w(GET POST PUT PATCH DELETE HEAD OPTIONS)
    @methods = if methods != "*"
      methods.map! { |method| method.to_s.upcase }.tap { |m|
        if (invalid_methods = m - @default_methods).any?
          raise ArgumentError, "Unsupported method passed to Rage::Cors: #{invalid_methods[0]}"
        end
      }.join(", ")
    elsif @allow_credentials
      @default_methods.join(", ")
    else
      "*"
    end

    if @allow_credentials
      raise ArgumentError, "Rage::Cors requires you to explicitly list allowed headers when using `allow_credentials: true`" if @allow_headers == "*"
      raise ArgumentError, "Rage::Cors requires you to explicitly list exposed headers when using `allow_credentials: true`" if @expose_headers == "*"
    end

    @origins = []
    origins.each do |origin|
      if origin == "*"
        @origins = "*"
        break
      elsif origin.is_a?(Regexp) || origin =~ /^\S+:\/\//
        @origins << origin
      else
        @origins << "https://#{origin}" << "http://#{origin}"
      end
    end

    @cors_check = create_cors_proc
    @cors_response = [204, create_headers, []]
  end

  private

  def create_headers
    headers = {
      "access-control-allow-origin" => "",
      "access-control-allow-methods" => @methods
    }

    if @allow_headers
      headers["access-control-allow-headers"] = @allow_headers
    end
    if @expose_headers
      headers["access-control-expose-headers"] = @expose_headers
    end
    if @max_age
      headers["access-control-max-age"] = @max_age
    end
    if @allow_credentials
      headers["access-control-allow-credentials"] = @allow_credentials
    end

    headers
  end

  def create_cors_proc
    if @origins == "*"
      ->(env) { env["HTTP_ORIGIN"] }
    else
      origins_eval = @origins.map { |origin|
        origin.is_a?(Regexp) ?
          "origin =~ /#{origin}/.freeze" :
          "origin == '#{origin}'.freeze"
      }.join(" || ")

      eval <<-RUBY
        ->(env) do
          origin = env["HTTP_ORIGIN".freeze]
          origin if #{origins_eval}
        end
      RUBY
    end
  end
end

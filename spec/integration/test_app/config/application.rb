require "bundler/setup"
require "rage"
Bundler.require(*Rage.groups)

require "rage/all"

class TestMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["HTTP_TEST_MIDDLEWARE"]
      [206, {}, ["response from middleware"]]
    else
      @app.call(env)
    end
  end
end

Rage.configure do
  config.middleware.use TestMiddleware
  config.public_file_server.enabled = !!ENV["ENABLE_FILE_SERVER"]

  if ENV["ENABLE_REQUEST_ID_MIDDLEWARE"]
    config.middleware.use Rage::RequestId
  end

  if ENV["WEBSOCKETS_PROTOCOL"]
    config.cable.protocol = ENV["WEBSOCKETS_PROTOCOL"].to_sym
  end

  if ENV["ENABLE_CUSTOM_LOG_CONTEXT"]
    config.log_tags << Rage.env

    config.log_context << proc do |env|
      if env["HTTP_RAISE_LOG_CONTEXT_EXCEPTION"]
        raise "test"
      else
        { current_time: Time.now.to_i }
      end
    end
  end
end

require "rage/setup"

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

  config.cable.protocol = if ENV["WEBSOCKETS_PROTOCOL"]
    ENV["WEBSOCKETS_PROTOCOL"].to_sym
  else
    :raw_websocket_json
  end

  if ENV["ENABLE_CUSTOM_LOG_CONTEXT"]
    config.log_tags << Rage.env

    config.log_context << proc do
      { current_time: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) }
    end
  end

  if ENV["ENABLE_CUSTOM_INVALID_LOG_CONTEXT"]
    config.log_context << proc do
      raise "test"
    end
  end

  config.after_initialize do
    config.deferred.enqueue_middleware.use EnqueueMiddleware1
    config.deferred.enqueue_middleware.use EnqueueMiddleware2

    config.deferred.perform_middleware.use PerformMiddleware1
    config.deferred.perform_middleware.use PerformMiddleware2
  end
end

require "rage/setup"

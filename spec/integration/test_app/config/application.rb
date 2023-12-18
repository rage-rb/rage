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
end

require "rage/setup"

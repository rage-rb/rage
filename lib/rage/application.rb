# frozen_string_literal: true

class Rage::Application
  def initialize(router)
    @router = router
  end

  def call(env)
    handler = @router.lookup(env)

    if handler
      handler[:handler].call(env, handler[:params])
    else
      [404, {}, ["Not Found"]]
    end

  rescue => e
    [500, {}, ["#{e.class}:#{e.message}\n\n#{e.backtrace.join("\n")}"]]
  end
end

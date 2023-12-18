# frozen_string_literal: true

##
# The middleware wraps every request in a Fiber and implements the custom defer protocol with Iodine.
# Scheduling fibers in a middleware allows the framework to be compatibe with custom Rack middlewares.
#
class Rage::FiberWrapper
  def initialize(app)
    Iodine.on_state(:on_start) do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
    end
    @app = app
  end

  def call(env)
    fiber = Fiber.schedule do
      @app.call(env)
    ensure
      Iodine.publish(Fiber.current.__get_id, "", Iodine::PubSub::PROCESS) if Fiber.current.__yielded?
    end

    if fiber.alive?
      [:__http_defer__, fiber]
    else
      fiber.__get_result
    end
  end
end

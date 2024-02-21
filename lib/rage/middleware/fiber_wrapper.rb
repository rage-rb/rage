# frozen_string_literal: true

##
# The middleware wraps every request in a separate Fiber. It should always be on the top of the middleware stack,
# as it implements a custom defer protocol, which may break middlewares located above.
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
      # notify Iodine the request can now be resumed
      Iodine.publish(Fiber.current.__get_id, "", Iodine::PubSub::PROCESS)
    end

    # the fiber encountered blocking IO and yielded; instruct Iodine to pause the request
    if fiber.alive?
      [:__http_defer__, fiber]
    else
      fiber.__get_result
    end
  end
end

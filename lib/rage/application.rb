# frozen_string_literal: true

class Rage::Application
  def initialize(router)
    Iodine.on_state(:on_start)  do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
    end
    @router = router
  end

  def call(env)
    fiber = Fiber.schedule do
      handler = @router.lookup(env)

      if handler
        handler[:handler].call(env, handler[:params])
      else
        [404, {}, ["Not Found"]]
      end

    rescue => e
      [500, {}, ["#{e.class}:#{e.message}\n\n#{e.backtrace.join("\n")}"]]

    ensure
      # notify Iodine the request can now be served
      Iodine.publish(env["IODINE_REQUEST_ID"], "")
    end

    # the fiber encountered blocking IO and yielded; instruct Iodine to pause the request;
    if fiber.alive?
      [:__http_defer__, fiber]
    else
      fiber.__get_result
    end
  end
end

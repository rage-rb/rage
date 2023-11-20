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
      init_logger

      handler = @router.lookup(env)

      response = if handler
        params = Rage::ParamsParser.prepare(env, handler[:params])
        handler[:handler].call(env, params)
      else
        [404, {}, ["Not Found"]]
      end

    rescue => e
      response = [500, {}, ["#{e.class}:#{e.message}\n\n#{e.backtrace.join("\n")}"]]

    ensure
      finalize_logger(env, response, params)
      Iodine.publish(env["IODINE_REQUEST_ID"], "") # notify Iodine the request can now be served
    end

    # the fiber encountered blocking IO and yielded; instruct Iodine to pause the request;
    if fiber.alive?
      [:__http_defer__, fiber]
    else
      fiber.__get_result
    end
  end

  private

  DEFAULT_LOG_CONTEXT = {}.freeze
  private_constant :DEFAULT_LOG_CONTEXT

  def init_logger
    Thread.current[:rage_logger] = {
      tags: [Iodine::Rack::Utils.gen_request_tag],
      context: DEFAULT_LOG_CONTEXT,
      request_start: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    }
  end

  def finalize_logger(env, response, params)
    logger = Thread.current[:rage_logger]

    duration = (
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - logger[:request_start]) * 1000
    ).round(2)

    logger[:final] = { env:, params:, response:, duration: }
    Rage.logger.info("")
  end
end

# frozen_string_literal: true

class Rage::Application
  def initialize(router)
    @router = router
    @exception_app = build_exception_app
  end

  def call(env)
    init_logger

    handler = @router.lookup(env)

    response = if handler
      params = Rage::ParamsParser.prepare(env, handler[:params])
      handler[:handler].call(env, params)
    else
      [404, {}, ["Not Found"]]
    end

  rescue Rage::Errors::BadRequest => e
    response = @exception_app.call(400, e)

  rescue Exception => e
    response = @exception_app.call(500, e)

  ensure
    finalize_logger(env, response, params)
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
    logger[:final] = nil
  end

  def build_exception_app
    if Rage.env.development?
      ->(status, e) do
        exception_str = "#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}"
        Rage.logger.error(exception_str)
        [status, {}, [exception_str]]
      end
    else
      ->(status, e) do
        exception_str = "#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}"
        Rage.logger.error(exception_str)
        [status, {}, []]
      end
    end
  end
end

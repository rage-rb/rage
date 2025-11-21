# frozen_string_literal: true

class Rage::Application
  def initialize(router)
    @router = router
    @exception_app = build_exception_app
    @log_processor = Rage.__log_processor
  end

  def call(env)
    @log_processor.init_request_logger(env)

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
    @log_processor.finalize_request_logger(env, response, params)
  end

  private

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

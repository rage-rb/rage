# frozen_string_literal: true

class Rage::Reloader
  def initialize(app)
    @app = app
  end

  def call(env)
    with_reload do
      @app.call(env)
    end
  rescue Exception => e
    exception_str = "#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}"
    puts(exception_str)
    [500, {}, [exception_str]]
  end

  private

  def with_reload
    if Rage.code_loader.check_updated!
      Fiber.new(blocking: true) {
        Rage.code_loader.reload
        yield
      }.resume
    else
      yield
    end
  end
end

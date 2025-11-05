# frozen_string_literal: true

class Rage::Reloader
  def initialize(app)
    Iodine.on_state(:on_start) do
      Rage.code_loader.check_updated!
    end

    @app = app
    @mutex = Mutex.new
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
    @mutex.synchronize do
      Rage.code_loader.reload if Rage.code_loader.check_updated!
    end

    yield
  end
end

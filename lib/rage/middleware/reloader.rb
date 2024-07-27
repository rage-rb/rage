# frozen_string_literal: true

class Rage::Reloader
  def initialize(app)
    @app = app
  end

  def call(env)
    Rage.code_loader.reload
    @app.call(env)
  rescue Exception => e
    exception_str = "#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}"
    puts(exception_str)
    [500, {}, [exception_str]]
  end
end

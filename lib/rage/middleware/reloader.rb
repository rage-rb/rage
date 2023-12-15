# frozen_string_literal: true

class Rage::Reloader
  def initialize(app)
    @app = app
  end

  def call(env)
    Rage.code_loader.reload
    @app.call(env)
  end
end

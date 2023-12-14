# frozen_string_literal: true

class Rage::Reloader
  def initialize(app)
    @app = app
  end

  def call(env)
    reload_application_code
    @app.call(env)
  end

  private

  def reload_application_code
    Rage.code_loader.reload
    Rage.__router.reset_routes
    load("#{Rage.root}/config/routes.rb")
  end
end

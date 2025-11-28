# frozen_string_literal: true

class Rage::BodyFinalizer
  def initialize(app)
    @app = app
  end

  def call(env)
    response = @app.call(env)
    response[2].close

    response
  end
end

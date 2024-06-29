# frozen_string_literal: true

class Rage::OriginValidator
  def initialize(app, *allowed_origins)
    @app = app
    @validator = build_validator(allowed_origins)
  end

  def call(env)
    if @validator.call(env)
      @app.call(env)
    else
      Rage.logger.error("Request origin not allowed: #{env["HTTP_ORIGIN"]}")
      [404, {}, ["Not Found"]]
    end
  end

  private

  def build_validator(allowed_origins)
    if allowed_origins.empty?
      ->(env) { false }
    else
      origins_eval = allowed_origins.map { |origin|
        origin.is_a?(Regexp) ?
          "origin =~ /#{origin.source}/.freeze" :
          "origin == '#{origin}'.freeze"
      }.join(" || ")

      eval <<-RUBY
        ->(env) do
          origin = env["HTTP_ORIGIN".freeze]
          #{origins_eval}
        end
      RUBY
    end
  end
end

# frozen_string_literal: true

class Rage::OriginValidator
  def initialize(app, *allowed_origins, allow_same_origin_as_host: true)
    @app = app
    @validator = build_validator(allowed_origins, allow_same_origin_as_host)
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

  def build_validator(allowed_origins, allow_same_origin_as_host)
    if allowed_origins.empty? && !allow_same_origin_as_host
      ->(env) { false }
    else
      origins_eval = []

      same_origin_eval = if allow_same_origin_as_host
        origins_eval << "is_same_origin"

        <<~RUBY
          host = env["HTTP_HOST"]

          is_same_origin = if host.nil?
            false
          elsif origin.start_with?("https://")
            origin.size == host.size + 8 && origin.end_with?(host)
          elsif origin.start_with?("http://")
            origin.size == host.size + 7 && origin.end_with?(host)
          end
        RUBY
      end

      origins_eval += allowed_origins.map do |configured_origin|
        configured_origin.is_a?(Regexp) ?
          "origin =~ /#{configured_origin.source}/" :
          "origin == '#{configured_origin}'"
      end

      eval <<~RUBY
        # frozen_string_literal: true

        ->(env) do
          origin = env["HTTP_ORIGIN"]
          return false unless origin

          #{same_origin_eval}
          #{origins_eval.join(" || ")}
        end
      RUBY
    end
  end
end

# frozen_string_literal: true

class RenderersController < RageController::API
  def html
    render html: <<~HTML
      <div>HTML content</div>
    HTML
  end

  def erb
    @name = "World"
    render erb: "renderers/erb", status: 202
  end

  def erb_over_sse
    @name = "World"
    render erb: "renderers/erb", sse: true
  end

  def json
    render json: { message: "Hello, World" }, status: :created
  end
end

class StaticController < RageController::API
  def index
    headers["x-sendfile"] = params[:file]
    headers["x-sendfile-root"] = Rage.root.join("app/assets").to_s

    headers["cache-control"] = "max-age=604800"
    headers["rage-custom-header"] = "qwerty"

    head :ok
  end
end

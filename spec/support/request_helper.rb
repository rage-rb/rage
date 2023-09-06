# frozen_string_literal: true

module RequestHelper
  def router
    @router ||= Rage::Router::Backend.new
  end

  def perform_get_request(path, host: nil)
    perform_request("GET", path, host)
  end

  def perform_post_request(path, host: nil)
    perform_request("POST", path, host)
  end

  private

  def perform_request(method, path, host)
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "HTTP_HOST" => host
    }
    handler = router.lookup(env)

    [handler[:handler].call(env, handler[:params]), handler[:params]] if handler
  end
end

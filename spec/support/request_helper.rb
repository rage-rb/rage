# frozen_string_literal: true

module RequestHelper
  def router
    @router ||= Rage::Router::Backend.new
  end

  def perform_get_request(path, host: nil, params: {})
    perform_request("GET", path, host, params)
  end

  def perform_head_request(path, host: nil, params: {})
    perform_request("HEAD", path, host, params)
  end

  def perform_post_request(path, host: nil, params: {})
    perform_request("POST", path, host, params)
  end

  private

  def perform_request(method, path, host, params)
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "HTTP_HOST" => host
    }
    handler = router.lookup(env)

    [handler[:handler].call(env, handler[:params]), params.merge(handler[:params])] if handler
  end
end

# frozen_string_literal: true

module RequestHelper
  def router
    @router ||= Rage::Router::Backend.new
  end

  def perform_get_request(path, host: nil, params: {}, body: nil)
    perform_request("GET", path, host, params, body)
  end

  def perform_head_request(path, host: nil, params: {}, body: nil)
    perform_request("HEAD", path, host, params, body)
  end

  def perform_post_request(path, host: nil, params: {}, body: nil)
    perform_request("POST", path, host, params, body)
  end

  private

  def perform_request(method, path, host, params, body)
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "HTTP_HOST" => host,
      "rack.input" => body || StringIO.new
    }
    handler = router.lookup(env)

    [handler[:handler].call(env, handler[:params]), params.merge(handler[:params])] if handler
  end
end

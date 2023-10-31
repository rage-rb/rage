# frozen_string_literal: true

class Rage::ParamsParser
  def self.prepare(env, url_params)
    has_body, query_string, content_type = env["IODINE_HAS_BODY"], env["QUERY_STRING"], env["CONTENT_TYPE"]

    query_params = Iodine::Rack::Utils.parse_nested_query(query_string) if query_string != ""
    unless has_body
      if query_params
        return query_params.merge!(url_params)
      else
        return url_params
      end
    end

    request_params = if content_type.start_with?("application/json")
      json_parse(env["rack.input"].read)
    elsif content_type.start_with?("application/x-www-form-urlencoded")
      Iodine::Rack::Utils.parse_urlencoded_nested_query(env["rack.input"].read)
    else
      Iodine::Rack::Utils.parse_multipart(env["rack.input"], content_type)
    end

    if request_params && !query_params
      request_params.merge!(url_params)
    elsif request_params && query_params
      request_params.merge!(query_params, url_params)
    else
      url_params
    end

  rescue => e
    raise Rage::Errors::BadRequest
  end

  if defined?(::FastJsonparser)
    def self.json_parse(json)
      FastJsonparser.parse(json, symbolize_keys: true)
    end
  else
    def self.json_parse(json)
      JSON.parse(json, symbolize_names: true)
    end
  end
end

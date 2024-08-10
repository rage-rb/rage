# frozen_string_literal: true

require "time"

class Rage::Request
  # @private
  def initialize(env)
    @env = env
  end

  # Get the request headers.
  # @example
  #   request.headers["Content-Type"] # => "application/json"
  #   request.headers["Connection"] # => "keep-alive"
  def headers
    @headers ||= Headers.new(@env)
  end

  # Check if the request is fresh.
  # @param etag [String] The etag of the requested resource.
  # @param last_modified [Time] The last modified time of the requested resource.
  # @return [Boolean] True if the request is fresh, false otherwise.
  # @example
  #  request.fresh?(etag: "123", last_modified: Time.utc(2023, 12, 15))
  #  request.fresh?(last_modified: Time.utc(2023, 12, 15))
  #  request.fresh?(etag: "123")
  def fresh?(etag:, last_modified:)
    # Always render response when no freshness information
    # is provided in the request.
    return false unless if_none_match || if_not_modified_since

    etag_matches?(
      requested_etags: if_none_match, response_etag: etag
    ) && not_modified?(
      request_not_modified_since: if_not_modified_since,
      response_last_modified: last_modified
    )
  end

  # Returns the full URL of the request.
  # @example
  #   request.url # => "https://example.com/users?show_archived=true"
  def url
    scheme = @env["rack.url_scheme"]
    host = @env["SERVER_NAME"]
    port = @env["SERVER_PORT"]
    path = @env["PATH_INFO"]
    query_string = @env["QUERY_STRING"]

    port_part = (scheme == "http" && port == "80") || (scheme == "https" && port == "443") ? "" : ":#{port}"
    query_part = query_string.empty? ? "" : "?#{query_string}"

    "#{scheme}://#{host}#{port_part}#{path}#{query_part}"
  end

  # Returns the path of the request.
  # @example
  #   request.path # => "/users"
  def path
    @env["PATH_INFO"]
  end

  # Returns the full path including the query string.
  # @example
  #   request.fullpath # => "/users?show_archived=true"
  def fullpath
    path = @env["PATH_INFO"]
    query_string = @env["QUERY_STRING"]
    query_string.empty? ? path : "#{path}?#{query_string}"
  end

  # Returns the user agent of the request.
  # @example
  #  request.user_agent # => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
  def user_agent
    headers["HTTP_USER_AGENT"]
  end

  private

  def if_none_match
    headers["HTTP_IF_NONE_MATCH"]
  end

  def if_not_modified_since
    headers["HTTP_IF_MODIFIED_SINCE"] ? Time.httpdate(headers["HTTP_IF_MODIFIED_SINCE"]) : nil
  rescue ArgumentError
    nil
  end

  def etag_matches?(requested_etags:, response_etag:)
    requested_etags = requested_etags ? requested_etags.split(",").each(&:strip!) : []

    return true if requested_etags.empty?
    return false if response_etag.nil?

    requested_etags.include?(response_etag) || requested_etags.include?("*")
  end

  def not_modified?(request_not_modified_since:, response_last_modified:)
    return true if request_not_modified_since.nil?
    return false if response_last_modified.nil?

    request_not_modified_since >= response_last_modified
  end

  # @private
  class Headers
    HTTP = "HTTP_"

    def initialize(env)
      @env = env
    end

    def [](requested_header)
      if requested_header.start_with?(HTTP)
        @env[requested_header]
      else
        (requested_header = requested_header.tr("-", "_")).upcase!

        if "CONTENT_TYPE" == requested_header || "CONTENT_LENGTH" == requested_header
          @env[requested_header]
        else
          @env["#{HTTP}#{requested_header}"]
        end
      end
    end

    def inspect
      headers = @env.select { |k| k == "CONTENT_TYPE" || k == "CONTENT_LENGTH" || k.start_with?(HTTP) }
      "#<#{self.class.name} @headers=#{headers.inspect}"
    end
  end # class Headers
end

# frozen_string_literal: true

require "time"

class Rage::Request
  # @private
  # regexp to match against a ip address
  IP_HOST_REGEXP = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
  # @private
  # HTTP methods from [RFC 2616: Hypertext Transfer Protocol -- HTTP/1.1](https://www.ietf.org/rfc/rfc2616.txt)
  RFC2616 = %w(OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT)
  # @private
  # HTTP methods from [RFC 2518: HTTP Extensions for Distributed Authoring -- WEBDAV](https://www.ietf.org/rfc/rfc2518.txt)
  RFC2518 = %w(PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK)
  # @private
  # HTTP methods from [RFC 3253: Versioning Extensions to WebDAV](https://www.ietf.org/rfc/rfc3253.txt)
  RFC3253 = %w(VERSION-CONTROL REPORT CHECKOUT CHECKIN UNCHECKOUT MKWORKSPACE UPDATE LABEL MERGE BASELINE-CONTROL MKACTIVITY)
  # @private
  # HTTP methods from [RFC 3648: WebDAV Ordered Collections Protocol](https://www.ietf.org/rfc/rfc3648.txt)
  RFC3648 = %w(ORDERPATCH)
  # @private
  # HTTP methods from [RFC 3744: WebDAV Access Control Protocol](https://www.ietf.org/rfc/rfc3744.txt)
  RFC3744 = %w(ACL)
  # @private
  # HTTP methods from [RFC 5323: WebDAV SEARCH](https://www.ietf.org/rfc/rfc5323.txt)
  RFC5323 = %w(SEARCH)
  # @private
  # HTTP methods from [RFC 4791: Calendaring Extensions to WebDAV](https://www.ietf.org/rfc/rfc4791.txt)
  RFC4791 = %w(MKCALENDAR)
  # @private
  # HTTP methods from [RFC 5789: PATCH Method for HTTP](https://www.ietf.org/rfc/rfc5789.txt)
  RFC5789 = %w(PATCH)

  # @private
  # Set data structure of all RFC defined HTTP headers
  KNOWN_HTTP_METHODS = (RFC2616 + RFC2518 + RFC3253 + RFC3648 + RFC3744 + RFC5323 + RFC4791 + RFC5789).to_set

  # @private
  # @param env [Hash] Rack env
  # @param controller [RageController::API]
  def initialize(env, controller: nil)
    @env = env
    @controller = controller
  end

  # Check if the request was made using TLS/SSL which is if http or https protocol is used inside the URL.
  # @return [Boolean] true if the request is TLS/SSL, false otherwise
  def ssl?
    rack_request.ssl?
  end

  # Returns `https://` if this was an HTTPS request and `http://` otherwise.
  # @return [String] `https://` if this was an HTTP request over SSL/TLS or `http://` if it was an HTTP request
  def protocol
    ssl? ? "https://" : "http://"
  end

  # Get the hostname from the request.
  # @return [String] the hostname
  def host
    rack_request.host
  end

  # Get the port number from the request.
  # @return [Integer] the port number
  def port
    rack_request.port
  end

  # Get the query string from the request.
  # @return [String] the query string (empty string if no query)
  def query_string
    rack_request.query_string
  end

  # Get the Rack environment hash.
  # @return [Hash] the Rack env
  def env
    @env
  end

  # Check the HTTP request method to see if it was of type `GET`.
  # @return [Boolean] true if it was a `GET` request
  def get?
    rack_request.get?
  end

  # Check the HTTP request method to see if it was of type `POST`.
  # @return [Boolean] true if it was a `POST` request
  def post?
    rack_request.post?
  end

  # Check the HTTP request method to see if it was of type `PATCH`.
  # @return [Boolean] true if it was a `PATCH` request
  def patch?
    rack_request.patch?
  end

  # Check the HTTP request method to see if it was of type `PUT`.
  # @return [Boolean] true if it was a `PUT` request
  def put?
    rack_request.put?
  end

  # Check the HTTP request method to see if it was of type `DELETE`.
  # @return [Boolean] true if it was a `DELETE` request
  def delete?
    rack_request.delete?
  end

  # Check the HTTP request method to see if it was of type `HEAD`.
  # @return [Boolean] true if it was a `HEAD` request
  def head?
    rack_request.head?
  end

  # Get the full request URL.
  # @return [String] complete URL including protocol, host, path, and query
  def url
    rack_request.url
  end

  # Get the request path.
  # @return [String] the path component of the URL
  # @example
  #   request.path # => "/users"
  def path
    rack_request.path
  end

  # Get the request path including the query string.
  # @return [String] path with query string (if present)
  # @example
  #   request.fullpath # => "/users?show_archived=true"
  def fullpath
    rack_request.fullpath
  end

  # Get the `User-Agent` header value.
  # @return [String, nil] the user agent string or nil
  # @example
  #  request.user_agent # => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
  def user_agent
    rack_request.user_agent
  end

  # Get the content type of the request.
  # @return [String, nil] the MIME type of the request body
  def format
    rack_request.content_type
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

  # Get the domain part of the request.
  # @param tld_length [Integer] top-level domain length
  # @example Consider a URL like: `example.foo.gov`
  #   request.domain => "foo.gov"
  #   request.domain(0) => "gov"
  #   request.domain(2) => "example.foo.gov"
  def domain(tld_length = 1)
    extract_domain(host, tld_length)
  end

  # Get the HTTP method of the request. If the client is using the `Rack::MethodOverride`
  # middleware, then the `X-HTTP-Method-Override` header is checked first.
  # @return [String] The HTTP Method override header or the request method header
  def method
    check_method(@env["rack.methodoverride.original_method"] || @env["REQUEST_METHOD"])
  end

  # Get the unique request ID. By default, this ID is internally generated, and all log entries created during the request
  # are tagged with it. Alternatively, you can use the {Rage::RequestId} middleware to derive the ID from the `X-Request-Id` header.
  # @return [String] the request ID
  def request_id
    @env["rage.request_id"]
  end

  alias_method :uuid, :request_id

  # Get the route URI pattern matched for this request.
  # @return [String] the route URI pattern
  # @example
  #   # For a route defined as:
  #   #   get "/users/:id", to: "users#show"
  #   request.route_uri_pattern # => "/users/:id"
  def route_uri_pattern
    if @controller
      Rage::Router::Util.route_uri_pattern(@controller.class, @controller.action_name)
    else
      path
    end
  end

  def sse?
    @env["rack.upgrade?"] == :sse
  end

  private

  def rack_request
    @rack_request ||= Rack::Request.new(@env)
  end

  def check_method(name)
    if name
      if KNOWN_HTTP_METHODS.include?(name)
        name
      else
        raise(Rage::Errors::UnknownHTTPMethod, "#{name}, accepted HTTP methods are #{KNOWN_HTTP_METHODS.to_a}")
      end
    end
  end

  def extract_domain(host, tld_length)
    extract_domain_from(host, tld_length) if named_host?(host)
  end

  def extract_domain_from(host, tld_length)
    host.split(".").last(1 + tld_length).join(".")
  end

  def named_host?(host)
    !IP_HOST_REGEXP.match?(host)
  end

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

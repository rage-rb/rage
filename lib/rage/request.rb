# frozen_string_literal: true

require "time"
require "rack/request"
require 'forwardable'

class Rage::Request
  extend Forwardable
  attr_accessor :rack_request
  # get?/post?/patch?/put?/delete?/head?
  def_delegators :@rack_request,
                 :ssl?,
                 :host,
                 :port,
                 :query,
                 :query_string,
                 :env,
                 :get_header,
                 :get?,
                 :post?,
                 :patch?,
                 :put?,
                 :delete?,
                 :head?

  IP_HOST_REGEXP  = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
  # HTTP methods from [RFC 2616: Hypertext Transfer Protocol -- HTTP/1.1](https://www.ietf.org/rfc/rfc2616.txt)
  RFC2616 = %w(OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT)
  # HTTP methods from [RFC 2518: HTTP Extensions for Distributed Authoring -- WEBDAV](https://www.ietf.org/rfc/rfc2518.txt)
  RFC2518 = %w(PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK)
  # HTTP methods from [RFC 3253: Versioning Extensions to WebDAV](https://www.ietf.org/rfc/rfc3253.txt)
  RFC3253 = %w(VERSION-CONTROL REPORT CHECKOUT CHECKIN UNCHECKOUT MKWORKSPACE UPDATE LABEL MERGE BASELINE-CONTROL MKACTIVITY)
  # HTTP methods from [RFC 3648: WebDAV Ordered Collections Protocol](https://www.ietf.org/rfc/rfc3648.txt)
  RFC3648 = %w(ORDERPATCH)
  # HTTP methods from [RFC 3744: WebDAV Access Control Protocol](https://www.ietf.org/rfc/rfc3744.txt)
  RFC3744 = %w(ACL)
  # HTTP methods from [RFC 5323: WebDAV SEARCH](https://www.ietf.org/rfc/rfc5323.txt)
  RFC5323 = %w(SEARCH)
  # HTTP methods from [RFC 4791: Calendaring Extensions to WebDAV](https://www.ietf.org/rfc/rfc4791.txt)
  RFC4791 = %w(MKCALENDAR)
  # HTTP methods from [RFC 5789: PATCH Method for HTTP](https://www.ietf.org/rfc/rfc5789.txt)
  RFC5789 = %w(PATCH)

  HTTP_METHODS = RFC2616 + RFC2518 + RFC3253 + RFC3648 + RFC3744 + RFC5323 + RFC4791 + RFC5789

  HTTP_METHOD_LOOKUP = {}

  # Populate the HTTP method lookup cache.
  # TODO: Extract underscore method
  # HTTP_METHODS.each { |method|
  #   HTTP_METHOD_LOOKUP[method] = method.underscore.to_sym
  # }

  # @private
  def initialize(env)
    @env = env
    @rack_request = Rack::Request.new(env)
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
    @env["HTTP_USER_AGENT"]
  end

  def domain(tld_length = 1)
    extract_domain(host, tld_length)
  end

  def protocol
    (ssl? == "https://") ? "https://" : "http://"
  end

  # TODO: decide whether to rip `check_method` from rails
  # it checks the http method against a list of all known
  # http methods to ensure that it is a valid header?
  def method(*args)
    if args.empty?
      # @method ||= check_method(
      #   get_header("rack.methodoverride.original_method") || get_header("REQUEST_METHOD")
      # )
      @method ||= get_header("rack.methodoverride.original_method") || get_header("REQUEST_METHOD")
    else
      super
    end
  end

  def remote_ip(*args)
    @env['HTTP_X_FORWARDED_FOR']
  end

  private

  def extract_domain(host, tld_length)
    extract_domain_from(host, tld_length) if named_host?(host)
  end

  def extract_domain_from(host, tld_length)
    host.split(".").last(1 + tld_length).join(".")
  end

  def named_host?(host)
    !IP_HOST_REGEXP.match?(host)
  end

  def check_method(name)
    if name
      HTTP_METHOD_LOOKUP[name] || raise(Rage::Errors::UnknownHTTPMethod, "#{name}, accepted HTTP methods are #{HTTP_METHODS}")
    end

    name
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
          @env["#{HTTP_}#{requested_header}"]
        end
      end
    end

    def inspect
      headers = @env.select { |k| k == "CONTENT_TYPE" || k == "CONTENT_LENGTH" || k.start_with?(HTTP) }
      "#<#{self.class.name} @headers=#{headers.inspect}"
    end
  end # class Headers
end

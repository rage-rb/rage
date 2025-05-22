# frozen_string_literal: true

require "digest"
require "time"

class Rage::Response
  ETAG_HEADER = "ETag"
  LAST_MODIFIED_HEADER = "Last-Modified"

  # @private
  def initialize(headers, body)
    @headers = headers
    @body = body
  end

  # Returns the content of the response as a string. This contains the contents of any calls to `render`.
  # @return [String]
  def body
    @body[0]
  end

  # Returns the headers for the response.
  # @return [Hash]
  def headers
    @headers
  end

  # Returns ETag response header or nil if it's empty.
  #
  # @return [String, nil]
  def etag
    headers[Rage::Response::ETAG_HEADER]
  end

  # Sets ETag header to the response. Additionally, it will hashify the value using `Digest::SHA1.hexdigest`. Pass `nil` for resetting it.
  # @note ETag will be always Weak since no strong validation is implemented.
  # @note ArgumentError is raised if ETag value is neither `String`, nor `nil`
  # @param etag [String, nil] The etag of the resource in the response.
  def etag=(etag)
    raise ArgumentError, "Expected `String` but `#{etag.class}` is received" unless etag.is_a?(String) || etag.nil?

    headers[Rage::Response::ETAG_HEADER] = etag.nil? ? nil : "W/\"#{Digest::SHA1.hexdigest(etag)}\""
  end

  # Returns Last-Modified response header as `Time` object or `nil` if it's empty.
  # @note ArgumentError is raised if Last-Modified value is not compliant with RFC 2616 or if the Time class cannot represent specified date.
  #
  # @return [Time, nil]
  def last_modified
    headers[Rage::Response::LAST_MODIFIED_HEADER].nil? ? nil : Time.httpdate(headers[Rage::Response::LAST_MODIFIED_HEADER])
  end

  # Sets Last-Modified header to the response by calling httpdate on the argument.
  # @note ArgumentError is raised if +last_modified+ is not a `Time` object instance
  # @param last_modified [Time, nil] The last modified time of the resource in the response.
  def last_modified=(last_modified)
    raise ArgumentError, "Expected `Time` but `#{last_modified.class}` is received" unless last_modified.is_a?(Time) || last_modified.nil?

    headers[Rage::Response::LAST_MODIFIED_HEADER] = last_modified&.httpdate
  end
end

# frozen_string_literal: true

require "digest"

class Rage::Response
  ETAG_HEADER = "ETag"
  LAST_MODIFIED_HEADER = "Last-Modified"

  module Cache
    # @return [String, nil]
    def etag
      headers[Rage::Response::ETAG_HEADER]
    end

    # @param etag [String] The etag of the resource in the response.
    def etag=(etag)
      headers[Rage::Response::ETAG_HEADER] = Digest::SHA2.hexdigest(etag.to_s) if etag
    end

    # @return [Time, nil]
    def last_modified
      Time.httpdate(headers[Rage::Response::LAST_MODIFIED_HEADER]) if headers[Rage::Response::LAST_MODIFIED_HEADER]
    rescue ArgumentError
      nil
    end

    # @param last_modified [Time] The last modified time of the resource in the response.
    def last_modified=(last_modified)
      headers[Rage::Response::LAST_MODIFIED_HEADER] = last_modified.httpdate if last_modified.respond_to?(:httpdate)
    end
  end
end

# frozen_string_literal: true

require "digest"

module Rage
  module Http
    module Response
      module Cache
        ETAG_HEADER = "ETag"
        LAST_MODIFIED = "Last-Modified"

        def set_cache_headers(etag: nil, last_modified: nil)
          self.etag = etag
          self.last_modified = last_modified
        end

        def etag
          headers[Cache::ETAG_HEADER]
        end

        def etag=(etag)
          headers[Cache::ETAG_HEADER] = Digest::SHA2.hexdigest(etag.to_s) if etag
        end

        def last_modified
          Time.httpdate(headers[Cache::LAST_MODIFIED]) if headers[Cache::LAST_MODIFIED]
        end

        def last_modified=(last_modified)
          headers[Cache::LAST_MODIFIED] = last_modified.httpdate if last_modified.respond_to?(:httpdate)
        end
      end
    end
  end
end

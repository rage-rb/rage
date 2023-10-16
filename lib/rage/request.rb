# frozen_string_literal: true

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

  # @private
  class Headers
    def initialize(env)
      @env = env
    end

    def [](requested_header)
      if requested_header.start_with?("HTTP_")
        @env[requested_header]
      else
        (requested_header = requested_header.tr("-", "_")).upcase!

        if "CONTENT_TYPE" == requested_header || "CONTENT_LENGTH" == requested_header
          @env[requested_header]
        else
          @env["HTTP_#{requested_header}"]
        end
      end
    end

    def inspect
      headers = @env.select { |k| k == "CONTENT_TYPE" || k == "CONTENT_LENGTH" || k.start_with?("HTTP_") }
      "#<#{self.class.name} @headers=#{headers.inspect}"
    end
  end # class Headers
end

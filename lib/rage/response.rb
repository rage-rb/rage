# frozen_string_literal: true

class Rage::Response
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
end

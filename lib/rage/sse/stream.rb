# frozen_string_literal: true

class Rage::SSE::Stream
  attr_reader :id

  # TODO: close
  def initialize(id)
    # TODO: composite keys
    @id = id
  end
end

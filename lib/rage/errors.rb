module Rage::Errors
  class BadRequest < StandardError
  end

  class RouterError < StandardError
  end

  class UnknownHTTPMethod < StandardError
  end

  class InvalidCustomProxy < StandardError
  end
end

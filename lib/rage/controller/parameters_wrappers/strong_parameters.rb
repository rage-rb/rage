require 'singleton'

module ParametersWrappers
  class StrongParameters
    include Singleton

    def wrap_params(params)
      ActionController::Parameters.new(params)
    end
  end
end

# frozen_string_literal: true
module Rage
  def self.routes
    Rage::Router::DSL.new(__router)
  end

  def self.__router
    @__router ||= Rage::Router::Backend.new
  end

  module Router
    module Strategies
    end
  end
end

require_relative "rage/version"
require_relative "rage/router/strategies/host"
require_relative "rage/router/backend"
require_relative "rage/router/constrainer"
require_relative "rage/router/dsl"
require_relative "rage/router/handler_storage"
require_relative "rage/router/node"

# frozen_string_literal: true

require "json"
require "iodine"

module Rage
  def self.application
    Application.new(__router)
  end

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

module RageController
end

require_relative "rage/version"
require_relative "rage/application"
require_relative "rage/fiber"
require_relative "rage/fiber_scheduler"

require_relative "rage/router/strategies/host"
require_relative "rage/router/backend"
require_relative "rage/router/constrainer"
require_relative "rage/router/dsl"
require_relative "rage/router/handler_storage"
require_relative "rage/router/node"

require_relative "rage/controller/api"

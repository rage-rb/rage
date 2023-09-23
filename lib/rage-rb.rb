# frozen_string_literal: true

require "rack"
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

  def self.config
    @config ||= Rage::Configuration.new
  end

  def self.configure
    yield(config)
  end

  def self.env
    @__env ||= ENV["RAGE_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
  end

  def self.groups
    [:default, Rage.env.to_sym]
  end

  module Router
    module Strategies
    end
  end
end

module RageController
end

require_relative "rage/application"
require_relative "rage/fiber"
require_relative "rage/fiber_scheduler"
require_relative "rage/configuration"

require_relative "rage/router/strategies/host"
require_relative "rage/router/backend"
require_relative "rage/router/constrainer"
require_relative "rage/router/dsl"
require_relative "rage/router/handler_storage"
require_relative "rage/router/node"

require_relative "rage/controller/api"

# frozen_string_literal: true

require "rack"
require "json"
require "iodine"
require "pathname"

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

  def self.configure(&)
    config.instance_eval(&)
    config.__finalize
  end

  def self.env
    @__env ||= Rage::Env.new(ENV["RAGE_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development")
  end

  def self.groups
    [:default, Rage.env.to_sym]
  end

  def self.root
    @root ||= Pathname.new(".").expand_path
  end

  def self.logger
    @logger ||= config.logger
  end

  def self.load_middlewares(rack_builder)
    config.middleware.middlewares.each do |middleware, args, block|
      # in Rails compatibility mode we first check if the middleware is a part of the Rails middleware stack;
      # if it is - it is expected to be built using `ActionDispatch::MiddlewareStack::Middleware#build`, but Rack
      # expects the middleware to respond to `#new`, so we wrap the middleware into a helper module
      if Rage.config.internal.rails_mode
        rails_middleware = Rails.application.config.middleware.middlewares.find { |m| m.name == middleware.name }
        if rails_middleware
          wrapper = Module.new do
            extend self
            attr_accessor :middleware
            def new(app, *, &)
              middleware.build(app)
            end
          end
          wrapper.middleware = rails_middleware
          middleware = wrapper
        end
      end

      rack_builder.use(middleware, *args, &block)
    end
  end

  def self.code_loader
    @code_loader ||= Rage::CodeLoader.new
  end

  module Router
    module Strategies
    end
  end
end

module RageController
end

require_relative "rage/env"

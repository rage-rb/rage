# frozen_string_literal: true

require "rack"
require "json"
require "iodine"
require "pathname"

module Rage
  # Builds the Rage application with the configured middlewares.
  def self.application
    with_middlewares(Application.new(__router), config.middleware.middlewares)
  end

  # Builds the Rage application which delegates Rails requests to `Rails.application`.
  def self.multi_application
    Rage::Router::Util::Cascade.new(application, Rails.application)
  end

  # Shorthand to access {Rage::Cable Rage::Cable}.
  # @return [Rage::Cable]
  def self.cable
    Rage::Cable
  end

  # Shorthand to access {Rage::OpenAPI Rage::OpenAPI}.
  # @return [Rage::OpenAPI]
  def self.openapi
    Rage::OpenAPI
  end

  # Shorthand to access {Rage::Deferred Rage::Deferred}.
  # @return [Rage::Deferred]
  def self.deferred
    Rage::Deferred
  end

  # Shorthand to access {Rage::Events Rage::Events}.
  # @return [Rage::Events]
  def self.events
    Rage::Events
  end

  # Configure routes for the Rage application.
  # @return [Rage::Router::DSL::Handler]
  # @example
  #   Rage.routes.draw do
  #     root to: "users#index"
  #   end
  def self.routes
    Rage::Router::DSL.new(__router)
  end

  # @private
  def self.__router
    @__router ||= Rage::Router::Backend.new
  end

  # @private
  def self.__log_processor
    @__log_processor ||= Rage::LogProcessor.new
  end

  # Access the Rage configuration.
  # @return [Rage::Configuration] the Rage configuration instance.
  def self.config
    @config ||= Rage::Configuration.new
  end

  # Configure Rage using a block.
  # @example
  #   Rage.configure do |config|
  #     config.log_level = :debug
  #   end
  def self.configure(&)
    config.instance_eval(&)
    config.__finalize
  end

  # Access the current Rage environment.
  # @return [Rage::Env] the Rage environment instance
  # @example
  #   if Rage.env.development?
  #     puts "Running in development mode"
  #   end
  def self.env
    @__env ||= Rage::Env.new(ENV["RAGE_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development")
  end

  # Access the current Gem groups based on the Rage environment.
  def self.groups
    [:default, Rage.env.to_sym]
  end

  # Access the root path of the Rage application.
  # @return [Pathname] the root path
  def self.root
    @root ||= Pathname.new(".").expand_path
  end

  # Access the Rage logger.
  # @return [Rage::Logger] the Rage logger instance
  def self.logger
    @logger ||= config.logger
  end

  # Load middlewares into the Rage application.
  # @deprecated This method is deprecated and has been merged into `Rage.application`.
  def self.load_middlewares(_)
    puts "`Rage.load_middlewares` is deprecated and has been merged into `Rage.application`. Please remove this call."
  end

  # @private
  def self.code_loader
    @code_loader ||= Rage::CodeLoader.new
  end

  # @private
  def self.patch_active_record_connection_pool
    patch = proc do
      is_connected = ActiveRecord::Base.connection_pool rescue false
      if is_connected
        Iodine.on_state(:pre_start) { puts "INFO: Patching ActiveRecord::ConnectionPool" }
        Iodine.on_state(:on_start) do
          ActiveRecord::Base.connection_handler.connection_pool_list(:all).each do |pool|
            pool.extend(Rage::Ext::ActiveRecord::ConnectionPool)
            pool.__init_rage_extension
          end
        end
      else
        puts "WARNING: DB connection is not established - can't patch ActiveRecord::ConnectionPool"
      end
    end

    if Rage.config.internal.rails_mode
      Rails.configuration.after_initialize(&patch)
    else
      patch.call
    end
  end

  # Load Rake tasks for the Rage application.
  def self.load_tasks
    Rage::Tasks.init
  end

  # @private
  def self.with_middlewares(app, middlewares)
    middlewares.reverse.inject(app) do |next_in_chain, (middleware, args, block)|
      # in Rails compatibility mode we first check if the middleware is a part of the Rails middleware stack;
      # if it is - it is expected to be built using `ActionDispatch::MiddlewareStack::Middleware#build`
      if Rage.config.internal.rails_mode
        rails_middleware = Rails.application.config.middleware.middlewares.find { |m| m.name == middleware.name }
      end

      if rails_middleware
        rails_middleware.build(next_in_chain)
      else
        middleware.new(next_in_chain, *args, &block)
      end
    end
  end

  class << self
    alias_method :configuration, :config
  end

  module Router
    module Strategies
    end

    module DSLPlugins
    end
  end

  module Ext
    module ActiveRecord
      autoload :ConnectionPool, "rage/ext/active_record/connection_pool"
    end
  end

  autoload :Tasks, "rage/tasks"
  autoload :Cookies, "rage/cookies"
  autoload :Session, "rage/session"
  autoload :Cable, "rage/cable/cable"
  autoload :OpenAPI, "rage/openapi/openapi"
  autoload :Deferred, "rage/deferred/deferred"
  autoload :Events, "rage/events/events"
end

module RageController
end

require_relative "rage/env"
require_relative "rage/internal"

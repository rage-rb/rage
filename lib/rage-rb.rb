# frozen_string_literal: true

require "rack"
require "json"
require "iodine"
require "pathname"

module Rage
  def self.application
    with_middlewares(Application.new(__router), config.middleware.middlewares)
  end

  def self.multi_application
    Rage::Router::Util::Cascade.new(application, Rails.application)
  end

  def self.cable
    Rage::Cable
  end

  def self.openapi
    Rage::OpenAPI
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

  def self.load_middlewares(_)
    puts "`Rage.load_middlewares` is deprecated and has been merged into `Rage.application`. Please remove this call."
  end

  def self.code_loader
    @code_loader ||= Rage::CodeLoader.new
  end

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
end

module RageController
end

require_relative "rage/env"

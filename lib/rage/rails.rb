if Gem::Version.new(Rails.version) < Gem::Version.new(6)
  fail "Rage is only compatible with Rails 6+. Detected Rails version: #{Rails.version}."
end

# load the framework
require "rage/all"

# patch Rack
Iodine.patch_rack

# configure the framework
Rage.config.internal.rails_mode = true

# patch ActiveRecord's connection pool
if defined?(ActiveRecord)
  Rails.configuration.after_initialize do
    module ActiveRecord::ConnectionAdapters
      class ConnectionPool
        def connection_cache_key(_)
          Fiber.current
        end
      end
    end
  end
end

# set isolation level
if defined?(ActiveSupport::IsolatedExecutionState)
  ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
end

# release ActiveRecord connections on yield
if defined?(ActiveRecord)
  class Fiber
    def self.defer
      res = Fiber.yield

      if ActiveRecord::Base.connection_pool.active_connection?
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end

      res
    end
  end
end

# plug into Rails' Zeitwerk instance to reload the code
Rails.autoloaders.main.on_setup do
  if Iodine.running?
    Rage.code_loader.rails_mode_reload
  end
end

# patch `ActionDispatch::Reloader` to synchronize `reload!` calls
Rails.configuration.after_initialize do
  conditional_mutex = Module.new do
    def call(env)
      @mutex ||= Mutex.new
      if Rails.application.reloader.check!
        @mutex.synchronize { super }
      else
        super
      end
    end
  end

  ActionDispatch::Reloader.prepend(conditional_mutex)

  # use `ActionDispatch::Reloader` in development
  if Rage.env.development?
    Rage.config.middleware.use ActionDispatch::Reloader
  end
end

# clone Rails logger
Rails.configuration.after_initialize do
  if Rails.logger && !Rage.logger
    rails_logdev = Rails.logger.instance_variable_get(:@logdev)
    Rage.config.logger = Rage::Logger.new(rails_logdev.dev) if rails_logdev.is_a?(Logger::LogDevice)
  end
end

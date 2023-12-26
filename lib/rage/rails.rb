if Gem::Version.new(Rails.version) < Gem::Version.new(6)
  fail "Rage is only compatible with Rails 6+. Detected Rails version: #{Rails.version}."
end

# load the framework
require "rage/all"

# patch Rack
Iodine.patch_rack

# configure the framework
Rage.config.internal.rails_mode = true

# make sure log formatter is not used in console
Rails.application.console do
  Rage.config.internal.rails_console = true
  Rage.logger.level = Rage.logger.level if Rage.logger # trigger redefining log methods
end

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

# plug into Rails' Zeitwerk instance to reload the code
Rails.autoloaders.main.on_unload do
  Rage.code_loader.rails_mode_reload
end

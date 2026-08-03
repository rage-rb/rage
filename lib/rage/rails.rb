if Gem::Version.new(Rails.version) < Gem::Version.new(6)
  fail "Rage is only compatible with Rails 6+. Detected Rails version: #{Rails.version}."
end

# load the framework
require "rage/all"

# patch Rack
Iodine.patch_rack

# configure the framework
Rage.config.internal.rails_mode = true

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
      res = if Rails.application.reloader.check! || !$rage_code_loaded
        Fiber.new(blocking: true) { super }.resume
      else
        super
      end
      $rage_code_loaded = true

      res
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
    rails_logdev = Rails.logger.yield_self { |logger|
      logger.respond_to?(:broadcasts) ? logger.broadcasts.last : logger
    }.instance_variable_get(:@logdev)

    Rage.configure do
      config.logger = Rage::Logger.new(rails_logdev.dev) if rails_logdev.is_a?(Logger::LogDevice)
    end
  end
end

# load deferred routes in Rails 8+
if Rails::VERSION::MAJOR >= 8
  # reset Rage routes before Rails reloads routes
  routes_reloader_patch = Module.new do
    def reload!
      Rage.__router.reset_routes
      super
    end
  end
  Rails::Application::RoutesReloader.prepend(routes_reloader_patch)

  Rails.application.config.after_initialize do
    Rails.application.reload_routes!
  end
end

require "rage/ext/setup"

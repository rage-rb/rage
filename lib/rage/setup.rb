Iodine.patch_rack

if defined?(ActiveSupport::IsolatedExecutionState)
  ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
end

if defined?(ActiveRecord::ConnectionAdapters::ConnectionPool)
  ActiveRecord::ConnectionAdapters::ConnectionPool
  module ActiveRecord::ConnectionAdapters
    class ConnectionPool
      def connection_cache_key(_)
        Fiber.current
      end
    end
  end
end

require_relative "#{Rage.root}/config/environments/#{Rage.env}"

# Run application initializers
Dir["#{Rage.root}/config/initializers/**/*.rb"].each { |initializer| load(initializer) }

# Load application classes
Rage.code_loader.setup

require_relative "#{Rage.root}/config/routes"

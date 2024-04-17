# set ActiveSupport isolation level
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

# make `ActiveRecord::ConnectionPool` work correctly with fibers
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

# patch `ActiveRecord::ConnectionPool`
if defined?(ActiveRecord) && ENV["RAGE_PATCH_AR_POOL"]
  Rage.patch_active_record_connection_pool
end

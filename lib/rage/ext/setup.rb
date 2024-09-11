# set ActiveSupport isolation level
if defined?(ActiveSupport::IsolatedExecutionState)
  ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
end

# patch Active Record 6.0 to accept the role argument
if defined?(ActiveRecord) && ActiveRecord.version < Gem::Version.create("6.1")
  %i(active_connections? connection_pool_list clear_active_connections!).each do |m|
    ActiveRecord::Base.connection_handler.define_singleton_method(m) do |_ = nil|
      super()
    end
  end
end

# release ActiveRecord connections on yield
if defined?(ActiveRecord) && Rage.config.internal.patch_ar_pool?
  if ENV["RAGE_DISABLE_AR_WEAK_CONNECTIONS"]
    unless Rage.config.internal.should_manually_release_ar_connections?
      puts "WARNING: The RAGE_DISABLE_AR_WEAK_CONNECTIONS setting does not have any effect with Active Record 7.2+"
    end
    # no-op
  elsif Rage.config.internal.should_manually_release_ar_connections?
    class Fiber
      def self.defer(fileno)
        f = Fiber.current
        f.__awaited_fileno = fileno

        res = Fiber.yield

        if ActiveRecord::Base.connection_handler.active_connections?(:all)
          Iodine.defer do
            if fileno != f.__awaited_fileno || !f.alive?
              ActiveRecord::Base.connection_handler.connection_pool_list(:all).each { |pool| pool.release_connection(Fiber.current) }
            end
          end
        end

        res
      end
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
if defined?(ActiveRecord) && Rage.config.internal.patch_ar_pool?
  Rage.patch_active_record_connection_pool
end

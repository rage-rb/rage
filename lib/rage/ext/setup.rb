if defined?(ActiveRecord) && ActiveRecord.version < Gem::Version.create("6")
  fail "Rage is only compatible with Active Record 6+. Detected Active Record version: #{ActiveRecord.version}."
end

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
  elsif Rage.config.internal.should_manually_release_ar_connections?
    class Fiber
      def self.defer(fileno)
        f = Fiber.current
        f.__awaited_fileno = fileno

        res = Fiber.yield

        if ActiveRecord::Base.connection_handler.active_connections?(:all)
          Iodine.defer do
            if fileno != f.__awaited_fileno || !f.alive?
              ActiveRecord::Base.connection_handler.connection_pool_list(:all).each { |pool| pool.release_connection(f) }
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

# connect to the database in standalone mode
database_url, database_file = ENV["DATABASE_URL"], Rage.root.join("config/database.yml")
if defined?(ActiveRecord) && !Rage.config.internal.rails_mode && (database_url || database_file.exist?)
  # transform database URL to an object
  database_url_config = if database_url.nil?
    {}
  elsif ActiveRecord.version >= Gem::Version.create("6.1.0")
    ActiveRecord::Base.configurations
    ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(database_url).to_hash
  else
    ActiveRecord::ConnectionAdapters::ConnectionSpecification::ConnectionUrlResolver.new(database_url).to_hash
  end
  database_url_config.transform_keys!(&:to_s)

  # load config/database.yml
  if database_file.exist?
    database_file_config = begin
      require "yaml"
      require "erb"
      YAML.safe_load(ERB.new(database_file.read).result, aliases: true)
    end

    # merge database URL config into the file config (only if we have one database)
    database_file_config.transform_values! do |env_config|
      env_config.all? { |_, v| v.is_a?(Hash) } ? env_config : env_config.merge(database_url_config)
    end
  end

  if database_file_config
    ActiveRecord::Base.configurations = database_file_config
  else
    ActiveRecord::Base.configurations = { Rage.env.to_s => database_url_config }
  end

  ActiveRecord::Base.establish_connection(Rage.env.to_sym)

  if defined?(Rake)
    ActiveRecord::Base.logger = nil
  else
    ActiveRecord::Base.logger = Rage.logger
    ActiveRecord::Base.connection_pool.with_connection {} # validate the connection
  end
end

# patch `ActiveRecord::ConnectionPool`
if defined?(ActiveRecord) && !defined?(Rake) && Rage.config.internal.patch_ar_pool?
  Rage.patch_active_record_connection_pool
end

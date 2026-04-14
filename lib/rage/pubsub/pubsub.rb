##
# The module provides the support for multi-server setups for `Rage::Cable` and `Rage::SSE`. It allows for broadcasting messages across multiple servers or from different runtimes, e.g. Sidekiq.
#
# To use the module, add the `redis-client` gem to your Gemfile and create the environment-specific configuration in `config/pubsub.yml`:
#
# ```yaml
# production:
#   adapter: redis
#   url: <%= ENV["REDIS_URL"] %>
# ```
#
# The configuration supports the following options:
#
# - `adapter` (required): The adapter to use for Pub/Sub. The only supported value is `redis`.
# - `channel_prefix` (optional): A prefix to use for the Redis stream name. This can be useful if you want to share a Redis instance with other applications or services.
# - `pool_size` (optional): The size of the Redis connection pool. Default is 10.
# - `pool_timeout` (optional): The timeout in seconds for acquiring a connection from the pool. Default is 1 second.
#
# The rest of the options are passed directly to `redis-client`.
#
module Rage::PubSub
  module Adapters
    autoload :Redis, "rage/pubsub/adapters/redis"
  end
end

module Rage::PubSub
  module Adapters
    autoload :Base, "rage/pubsub/adapters/base"
    autoload :Redis, "rage/pubsub/adapters/redis"
  end
end

# frozen_string_literal: true

##
# The module enables communication between Rage instances across worker processes and nodes.
#
# It provides the infrastructure for multi-server setups for `Rage::Cable` and `Rage::SSE`, allowing broadcasting
# messages across multiple servers or from different runtimes, e.g. Sidekiq. It also exposes a low-level API via
# the {subscribe}, {unsubscribe}, and {publish} methods for direct inter-process communication.
#
# @note The low-level API is primarily intended for integrations and gems. Most applications should use
#   higher-level abstractions like {Rage::Cable Rage::Cable} or {Rage::SSE Rage::SSE} instead.
#
# ## Configuration
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
  BROADCASTER_ID = "pubsub"
  private_constant :BROADCASTER_ID

  module Relay
    def self.broadcast(channel, data)
      Iodine.publish(channel, data)
    end
  end
  private_constant :Relay

  class << self
    # @private
    def __initialize
      if (adapter = Rage.config.pubsub.adapter)
        adapter.add_broadcaster(BROADCASTER_ID, Relay)
        @__adapter = adapter
      end
    end

    # Subscribe to messages on a topic.
    #
    # @param topic [String, Array, #id] The channel name to subscribe to. Can be a string, an array,
    #   an Active Record model, or any object responding to `id`.
    # @param subscription_id [Object] A unique identifier for this subscription within the topic.
    #   Used to manage multiple subscriptions to the same topic and for cleanup via {unsubscribe}.
    # @yieldparam message [String] The raw message string.
    # @raise [ArgumentError] If a subscription with the same `topic` and `subscription_id` already exists.
    #
    # @example Subscribe to order updates
    #   Rage::PubSub.subscribe(topic: "orders", subscription_id: :order_listener) do |message|
    #     data = JSON.parse(message)
    #     puts "Received order update: #{data}"
    #   end
    def subscribe(topic:, subscription_id:, &block)
      if subscriptions.has_key?(topic) && subscriptions[topic].has_key?(subscription_id)
        raise ArgumentError, "A subscription with topic #{topic.inspect} and subscription_id #{subscription_id.inspect} already exists"
      end

      subscriptions[topic][subscription_id] = block
      subscribe_to_topic(topic)

      true
    end

    # Remove a subscription from a topic.
    #
    # @param topic [String, Array, #id] The channel name to unsubscribe from. Must match the value
    #   used when calling {subscribe}.
    # @param subscription_id [Object] The identifier of the subscription to remove.
    # @raise [ArgumentError] If the specified subscription does not exist.
    #
    # @example Unsubscribe from order updates
    #   Rage::PubSub.unsubscribe(topic: "orders", subscription_id: :order_listener)
    def unsubscribe(topic:, subscription_id:)
      if !subscriptions.has_key?(topic) || !subscriptions[topic].has_key?(subscription_id)
        raise ArgumentError, "No subscription found with topic #{topic.inspect} and subscription_id #{subscription_id.inspect}"
      end

      topic_subscriptions = subscriptions[topic]

      topic_subscriptions.delete(subscription_id)
      subscriptions.delete(topic) if topic_subscriptions.empty?

      true
    end

    # Publish a message to all subscribers of a topic.
    #
    # Messages are delivered to all subscribers across worker processes and nodes (when a PubSub
    # adapter is configured).
    #
    # @param message [String] The message to publish.
    # @param topic [String, Array, #id] The channel name to publish to. Can be a string, an array,
    #   an Active Record model, or any object responding to `id`.
    # @raise [ArgumentError] If message is not a String.
    #
    # @example Publish an order update
    #   Rage::PubSub.publish(JSON.generate({ id: 123, status: "shipped" }), topic: "orders")
    #
    # @example Publish to a model-based topic
    #   Rage::PubSub.publish("refresh", topic: current_user)
    def publish(message, topic:)
      raise ArgumentError, "Message must be a String, got #{message.class}" unless message.is_a?(String)

      serialized_topic = Rage::Internal.stream_name_for(topic)
      channel = "pubsub:#{serialized_topic}"

      Iodine.publish(channel, message) if Iodine.running?
      @__adapter&.publish(BROADCASTER_ID, channel, message)

      true
    end

    private

    def subscriptions
      @subscriptions ||= Hash.new { |h, k| h[k] = {} }
    end

    def subscribe_to_topic(topic)
      serialized_topic = Rage::Internal.stream_name_for(topic)
      return if Iodine.subscribed?("pubsub:#{serialized_topic}")

      Iodine.subscribe("pubsub:#{serialized_topic}") do |_, message|
        subscriptions[topic].each do |subscription_id, callback|
          callback.call(message)
        rescue => e
          Rage.logger.error(
            "PubSub callback failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}",
            subscription_id:
          )
        end
      end

      Iodine.on_state(:start_shutdown) do
        Iodine.unsubscribe("pubsub:#{serialized_topic}")
      end
    end
  end # class << self

  module Adapters
    autoload :Redis, "rage/pubsub/adapters/redis"
  end
end

if Rage.config.internal.initialized?
  Rage::PubSub.__initialize
else
  Rage.config.after_initialize { Rage::PubSub.__initialize }
end

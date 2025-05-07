# frozen_string_literal: true

require "securerandom"

if !defined?(RedisClient)
  fail <<~ERR

    Redis adapter depends on the `redis-client` gem. Add the following line to your Gemfile:
    gem "redis-client"

  ERR
end

class Rage::Cable::Adapters::Redis < Rage::Cable::Adapters::Base
  REDIS_STREAM_NAME = "rage:cable:messages"
  DEFAULT_REDIS_OPTIONS = { reconnect_attempts: [0.05, 0.1, 0.5] }
  REDIS_MIN_VERSION_SUPPORTED = Gem::Version.create(6)

  def initialize(config)
    @redis_stream = if (prefix = config.delete(:channel_prefix))
      "#{prefix}:#{REDIS_STREAM_NAME}"
    else
      REDIS_STREAM_NAME
    end

    @redis_config = RedisClient.config(**DEFAULT_REDIS_OPTIONS.merge(config))
    @server_uuid = SecureRandom.uuid

    redis_version = get_redis_version
    if redis_version < REDIS_MIN_VERSION_SUPPORTED
      raise "Redis adapter only supports Redis 6+. Detected Redis version: #{redis_version}."
    end

    @trimming_strategy = redis_version < Gem::Version.create("6.2.0") ? :maxlen : :minid

    pick_a_worker { poll }
  end

  def publish(stream_name, data)
    message_uuid = SecureRandom.uuid

    publish_redis.call(
      "XADD",
      @redis_stream,
      trimming_method, "~", trimming_value,
      "*",
      "1", stream_name,
      "2", data.to_json,
      "3", @server_uuid,
      "4", message_uuid
    )
  end

  private

  def publish_redis
    @publish_redis ||= @redis_config.new_client
  end

  def trimming_method
    @trimming_strategy == :maxlen ? "MAXLEN" : "MINID"
  end

  def trimming_value
    @trimming_strategy == :maxlen ? "10000" : ((Time.now.to_f - 5 * 60) * 1000).to_i
  end

  def get_redis_version
    service_redis = @redis_config.new_client
    version = service_redis.call("INFO").match(/redis_version:([[:graph:]]+)/)[1]

    Gem::Version.create(version)

  rescue RedisClient::Error => e
    puts "FATAL: Couldn't connect to Redis - all broadcasts will be limited to the current server."
    puts e.backtrace.join("\n")
    REDIS_MIN_VERSION_SUPPORTED

  ensure
    service_redis.close
  end

  def error_backoff_intervals
    @error_backoff_intervals ||= Enumerator.new do |y|
      y << 0.2 << 0.5 << 1 << 2 << 5
      loop { y << 10 }
    end
  end

  def poll
    unless Fiber.scheduler
      Fiber.set_scheduler(Rage::FiberScheduler.new)
    end

    Iodine.on_state(:start_shutdown) do
      @stopping = true
    end

    Fiber.schedule do
      read_redis = @redis_config.new_client
      last_id = (Time.now.to_f * 1000).to_i
      last_message_uuid = nil

      loop do
        data = read_redis.blocking_call(5, "XREAD", "COUNT", "100", "BLOCK", "5000", "STREAMS", @redis_stream, last_id)

        if data
          data[@redis_stream].each do |id, (_, stream_name, _, serialized_data, _, broadcaster_uuid, _, message_uuid)|
            if broadcaster_uuid != @server_uuid && message_uuid != last_message_uuid
              Rage.cable.__protocol.broadcast(stream_name, JSON.parse(serialized_data))
            end

            last_id = id
            last_message_uuid = message_uuid
          end
        end

      rescue RedisClient::Error => e
        Rage.logger.error("Subscriber error: #{e.message} (#{e.class})")
        sleep error_backoff_intervals.next
      rescue => e
        @stopping ? break : raise(e)
      else
        error_backoff_intervals.rewind
      end
    end
  end
end

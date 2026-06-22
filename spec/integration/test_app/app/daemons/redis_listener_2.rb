class RedisListener2 < Rage::Daemon
  def initialize
    Rage.logger << "[#{Process.pid}] starting #{self.class.name}\n"
    @redis = Redis.new(url: ENV["TEST_REDIS_URL"])
  end

  def perform
    @redis.subscribe("daemon:test:channel") do |on|
      on.message do |_, message|
        Rage.logger.info message.reverse
      end
    end
  end

  def cleanup
    @redis.close
  end
end

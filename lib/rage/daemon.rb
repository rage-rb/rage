# frozen_string_literal: true

##
# `Rage::Daemon` is an abstraction for running long-lived background processes alongside your application.
# Use daemons for tasks that need to run continuously, such as listening to message queues, consuming streaming APIs,
# or maintaining persistent connections to external services.
#
# The framework automatically manages daemon lifecycle:
# - Daemons are started when the server boots
# - If a daemon exits or crashes, Rage restarts it with exponential backoff
# - If a worker process dies, Rage restarts the daemon in another worker
# - On server shutdown, daemons are gracefully stopped
#
# ## Defining a Daemon
#
# Create a daemon by subclassing `Rage::Daemon` and implementing the {#perform} method:
#
# ```ruby
# class RedisListener < Rage::Daemon
#   def perform
#     redis = Redis.new
#
#     redis.subscribe("notifications") do |on|
#       on.message do |channel, message|
#         Rage::Cable.broadcast("notifications", message)
#       end
#     end
#   end
# end
# ```
#
# ## Registering Daemons
#
# Register daemons in your application configuration:
#
# ```ruby
# # config/application.rb
# Rage.configure do
#   config.daemons << RedisListener
# end
# ```
#
# ## Daemon Scope
#
# By default, daemons run in exactly one worker process per server. Use {scope scope} to change this behavior:
#
# ```ruby
# class MetricsCollector < Rage::Daemon
#   scope :worker
#
#   def perform
#     # runs in every worker process
#   end
# end
# ```
#
# ## Stopping a Daemon
#
# Return {Stop} from {#perform} to explicitly stop a daemon without triggering a restart:
#
# ```ruby
# class BatchProcessor < Rage::Daemon
#   def perform
#     while (batch = Batch.next_pending)
#       process(batch)
#     end
#
#     Stop  # all batches processed, stop the daemon
#   end
# end
# ```
#
# ## Cleanup
#
# Implement the `cleanup` method to release resources when a daemon stops or restarts:
#
# ```ruby
# class StreamConsumer < Rage::Daemon
#   def perform
#     @connection = StreamingAPI.connect
#     @connection.each { |event| process(event) }
#   end
#
#   def cleanup
#     @connection&.close
#   end
# end
# ```
#
# The `cleanup` method is called:
# - When {#perform} returns normally
# - When {#perform} raises an exception (before restart)
# - When the server is shutting down
#
class Rage::Daemon
  # A sentinel value that can be returned from {#perform} to explicitly stop the daemon.
  # When returned, the daemon will not be restarted.
  # @example
  #   def perform
  #     return Stop if shutdown_requested?
  #     # ...
  #   end
  Stop = Object.new

  INITIAL_BACKOFF = 0.1
  private_constant :INITIAL_BACKOFF

  MAX_BACKOFF = 30
  private_constant :MAX_BACKOFF

  BACKOFF_RESET_INTERVAL = 30
  private_constant :BACKOFF_RESET_INTERVAL

  class << self
    # @private
    attr_accessor :__level

    # Configures the scope at which the daemon runs.
    #
    # By default, daemons run in one worker process per server (`:node` scope).
    # Use this method to change the scope when a different behavior is needed.
    #
    # @param level [Symbol] the scope level
    # @option level :node One instance per server (default). Rage uses IPC to coordinate
    #   which worker runs the daemon. If that worker dies, the daemon restarts in another worker.
    # @option level :worker One instance per worker process. Use this when the daemon performs
    #   work that needs to run in parallel across workers.
    #
    # @example Running in every worker
    #   class MetricsCollector < Rage::Daemon
    #     scope :worker
    #
    #     def perform
    #       # runs in every worker process
    #     end
    #   end
    def scope(level)
      unless level == :worker || level == :node
        raise ArgumentError, "Invalid scope level: #{level.inspect}. Valid options are :node and :worker."
      end

      @__level = level
    end

    # @private
    def inherited(klass)
      klass.__level = __level
    end

    # @private
    def __perform
      if __level.nil? || __level == :node
        Rage::Internal.pick_a_worker(purpose: "daemon-#{name}") { __execute }
      else
        __execute
      end
    end

    private

    def __execute
      Iodine.on_state(:start_shutdown) do
        @__stopping = true
      end

      Fiber.schedule do
        backoff = INITIAL_BACKOFF

        Rage.logger.with_context(daemon: name) do
          loop do
            started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            begin
              instance = new
              result = instance.perform
              break if result.equal?(Stop) || @__stopping
              Rage.logger.warn("Daemon exited, restarting...")
            rescue => e
              break if @__stopping
              Rage.logger.error("Daemon failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
              Rage::Errors.report(e)
            ensure
              __cleanup(instance)
            end

            # reset backoff if ran successfully for a while
            backoff = INITIAL_BACKOFF if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at > BACKOFF_RESET_INTERVAL
            sleep(backoff / 2 + rand * backoff / 2)
            backoff = (backoff * 2).clamp(INITIAL_BACKOFF, MAX_BACKOFF)
          end
        end
      end
    end # class << self

    def __cleanup(instance)
      instance.cleanup if instance.respond_to?(:cleanup)
    rescue => e
      Rage.logger.error("Cleanup hook failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      Rage::Errors.report(e)
    end
  end

  # The main entry point for the daemon's work.
  #
  # Implement this method to define what the daemon does. The method should contain
  # the daemon's main loop or blocking operation. When this method returns normally,
  # Rage logs a warning and restarts the daemon. Return {Stop} to explicitly stop
  # the daemon without triggering a restart.
  #
  # @return [Object] return {Stop} to stop the daemon; any other return value triggers a restart
  # @example Listening to a Redis channel
  #   def perform
  #     redis = Redis.new
  #     redis.subscribe("events") do |on|
  #       on.message { |_, msg| handle(msg) }
  #     end
  #   end
  # @example Polling a queue
  #   def perform
  #     loop do
  #       message = queue.pop
  #       process(message)
  #     end
  #   end
  # @example Processing until complete
  #   def perform
  #     while (item = fetch_next_item)
  #       process(item)
  #     end
  #
  #     Stop
  #   end
  def perform
  end
end

Iodine.on_state(:on_start) do
  Fiber.set_scheduler(Rage::FiberScheduler.new) unless Fiber.scheduler
  Rage.config.daemons.klasses.each { |klass| klass.__perform }
end

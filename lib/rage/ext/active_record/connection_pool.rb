# frozen_string_literal: true

module Rage::Ext::ActiveRecord::ConnectionPool
  # items can be added but not removed
  class BlackHoleList
    def initialize(arr)
      @arr = arr
    end

    def <<(el)
      @arr << el
    end

    def shift
      nil
    end

    def length
      0
    end

    def to_a
      @arr
    end
  end

  def self.extended(instance)
    instance.class.alias_method :__checkout__, :checkout
    instance.class.alias_method :__remove__, :remove

    ActiveRecord::ConnectionAdapters::AbstractAdapter.attr_accessor(:__idle_since)
  end

  def __init_rage_extension
    # a map of fibers that are currently waiting for a
    # connection in the format of { Fiber => timestamp }
    @__blocked = {}

    # a map of fibers that are currently hodling connections
    # in the format of { Fiber => Connection }
    @__in_use = {}

    # a list of all DB connections that are currently idle
    @__connections = build_new_connections

    # how long a fiber can wait for a connection to become available
    @__checkout_timeout = checkout_timeout

    # how long a connection can be idle for before disconnecting
    @__idle_timeout = reaper.frequency

    # how often should we check for fibers that wait for a connection for too long
    @__timeout_worker_frequency = 0.5

    # reject fibers that wait for a connection for more than `@__checkout_timeout`
    Iodine.run_every((@__timeout_worker_frequency * 1_000).to_i) do
      if @__blocked.length > 0
        current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @__blocked.each do |fiber, blocked_since|
          if (current_time - blocked_since) > @__checkout_timeout
            @__blocked.delete(fiber)
            fiber.raise(ActiveRecord::ConnectionTimeoutError, "could not obtain a connection from the pool within #{@__checkout_timeout} seconds; all pooled connections were in use")
          end
        end
      end
    end

    # resume blocked fibers once connections become available
    Iodine.subscribe("ext:ar-connection-released") do
      if @__blocked.length > 0 && @__connections.length > 0
        f, _ = @__blocked.shift
        f.resume
      end
    end

    # unsubscribe on shutdown
    Iodine.on_state(:on_finish) do
      Iodine.unsubscribe("ext:ar-connection-released")
    end
  end

  # Returns true if there is an open connection being used for the current fiber.
  def active_connection?
    @__in_use[Fiber.current]
  end

  # Retrieve the connection associated with the current fiber, or obtain one if necessary.
  def connection
    @__in_use[Fiber.current] ||= @__connections.shift || begin
      fiber, blocked_since = Fiber.current, Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @__blocked[fiber] = blocked_since
      Fiber.yield

      @__connections.shift
    end
  end

  # Signal that the fiber is finished with the current connection and it can be returned to the pool.
  def release_connection(owner = Fiber.current)
    if (conn = @__in_use.delete(owner))
      conn.__idle_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @__connections << conn
      Iodine.publish("ext:ar-connection-released", "", Iodine::PubSub::PROCESS) if @__blocked.length > 0
    end

    conn
  end

  # Recover lost connections for the pool.
  def reap
    @__in_use.each do |fiber, conn|
      unless fiber.alive?
        if conn.active?
          conn.reset!
          release_connection(fiber)
        else
          @__in_use.delete(fiber)
          conn.disconnect!
          __remove__(conn)
          @__connections += build_new_connections(1)
          Iodine.publish("ext:ar-connection-released", "", Iodine::PubSub::PROCESS) if @__blocked.length > 0
        end
      end
    end
  end

  # Disconnect all connections that have been idle for at least
  # `minimum_idle` seconds. Connections currently checked out, or that were
  # checked in less than `minimum_idle` seconds ago, are unaffected.
  def flush(minimum_idle = @__idle_timeout)
    return if minimum_idle.nil? || @__connections.length == 0

    current_time, i = Process.clock_gettime(Process::CLOCK_MONOTONIC), 0
    while i < @__connections.length
      conn = @__connections[i]
      if conn.__idle_since && current_time - conn.__idle_since >= minimum_idle
        conn.__idle_since = nil
        conn.disconnect!
      end
      i += 1
    end
  end

  # Disconnect all currently idle connections. Connections currently checked out are unaffected.
  def flush!
    reap
    flush(-1)
  end

  # Yields a connection from the connection pool to the block.
  def with_connection
    yield connection
  ensure
    release_connection
  end

  # Returns an array containing the connections currently in the pool.
  def connections
    @__connections.to_a
  end

  # Returns true if a connection has already been opened.
  def connected?
    true
  end

  # Return connection pool's usage statistic.
  def stat
    {
      size: size,
      connections: size,
      busy: @__in_use.count { |fiber, _| fiber.alive? },
      dead: @__in_use.count { |fiber, _| !fiber.alive? },
      idle: @__connections.length,
      waiting: @__blocked.length,
      checkout_timeout: @__checkout_timeout
    }
  end

  # Disconnects all connections in the pool, and clears the pool.
  # Raises `ActiveRecord::ExclusiveConnectionTimeoutError` if unable to gain ownership of all
  # connections in the pool within a timeout interval (default duration is `checkout_timeout * 2` seconds).
  def disconnect(raise_on_acquisition_timeout = true, disconnect_attempts = 0)
    # allow request fibers to release connections, but block from acquiring new ones
    if disconnect_attempts == 0
      @__connections = BlackHoleList.new(@__connections)
    end

    # if some connections are in use, we will wait for up to `@__checkout_timeout * 2` seconds
    if @__in_use.length > 0 && disconnect_attempts <= @__checkout_timeout * 4
      Iodine.run_after(500) { disconnect(raise_on_acquisition_timeout, disconnect_attempts + 1) }
      return
    end

    pool_connections = @__connections.to_a

    # check if there are still some connections in use
    if @__in_use.length > 0
      raise(ActiveRecord::ExclusiveConnectionTimeoutError, "could not obtain ownership of all database connections") if raise_on_acquisition_timeout
      pool_connections += @__in_use.values
      @__in_use.clear
    end

    # disconnect all connections
    pool_connections.each do |conn|
      conn.disconnect!
      __remove__(conn)
    end

    # create a new pool
    @__connections = build_new_connections

    # notify blocked fibers that there are new connections available
    [@__blocked.length, @__connections.length].min.times do
      Iodine.publish("ext:ar-connection-released", "", Iodine::PubSub::PROCESS)
    end
  end

  # Disconnects all connections in the pool, and clears the pool.
  # The pool first tries to gain ownership of all connections. If unable to
  # do so within a timeout interval (default duration is `checkout_timeout * 2` seconds),
  # then the pool is forcefully disconnected without any regard for other connection owning fibers.
  def disconnect!
    disconnect(false)
  end

  # Check out a database connection from the pool, indicating that you want
  # to use it. You should call #checkin when you no longer need this.
  def checkout(_ = nil)
    connection
  end

  # Check in a database connection back into the pool, indicating that you no longer need this connection.
  def checkin(conn)
    fiber = @__in_use.key(conn)
    release_connection(fiber)
  end

  # Remove a connection from the connection pool. The connection will
  # remain open and active but will no longer be managed by this pool.
  def remove(conn)
    __remove__(conn)
    @__in_use.delete_if { |_, c| c == conn }
    @__connections.delete(conn)
  end

  def clear_reloadable_connections(raise_on_acquisition_timeout = true)
    disconnect(raise_on_acquisition_timeout)
  end

  def clear_reloadable_connections!
    disconnect(false)
  end

  def num_waiting_in_queue
    @__blocked.length
  end

  # Discards all connections in the pool (even if they're currently in use!),
  # along with the pool itself. Any further interaction with the pool is undefined.
  def discard!
    @__discarded = true
    (@__connections + @__in_use.values).each { |conn| conn.discard! }
  end

  def discarded?
    !!@__discarded
  end

  private

  def build_new_connections(num_connections = size)
    (1..num_connections).map do
      __checkout__.tap { |conn| conn.__idle_since = Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    end
  end
end

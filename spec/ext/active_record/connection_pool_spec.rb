# frozen_string_literal: true

require "active_record"

RSpec.describe Rage::Ext::ActiveRecord::ConnectionPool do
  subject { ActiveRecord::Base.connection_pool }

  before :all do
    skip("skipping external tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"

    Fiber.set_scheduler(Rage::FiberScheduler.new)

    # await internal fibers scheduled by the pool
    interceptor = Module.new do
      private def __intercepted_fibers
        @intercepted_fibers ||= []
      end

      def __await_internal_fibers
        __intercepted_fibers.clear
        yield
        Fiber.await(__intercepted_fibers)
      end

      def schedule
        super.tap { |f| __intercepted_fibers << f }
      end
    end

    Fiber.singleton_class.prepend(interceptor)
  end

  around do |example|
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::Base.connection_pool.extend(Rage::Ext::ActiveRecord::ConnectionPool)

    # we need to init the extension before every test to refresh the subscriptions
    subject.__init_rage_extension

    within_reactor do
      ensure_preconnected.call
      example.call
      -> {}
    end

    # cleanup - remove the connections
    subject.connections.each do |conn|
      conn.disconnect!
      subject.__remove__(conn)
    end
  end

  let(:pool_size) { 5 }
  let(:pool_size_config) do
    ActiveRecord.version < Gem::Version.create("8.1") ? { pool: pool_size } : { max_connections: pool_size }
  end
  let(:db_config) { { url: (ENV["TEST_PG_URL"]).to_s, **pool_size_config } }
  let(:ensure_preconnected) do
    -> do
      20.downto(0) do |i|
        if subject.connections.length != pool_size
          sleep 0.1
        elsif i == 0
          raise "Could not connect to the DB"
        else
          break
        end
      end
    end
  end

  describe "#with_connection" do
    it "checks out a connection" do
      subject.with_connection do |conn|
        expect(conn.execute("select 1")).to be_a(PG::Result)
      end
    end

    it "allows nested calls" do
      subject.with_connection do |conn|
        expect(conn.execute("select 1")).to be_a(PG::Result)
        subject.with_connection do |new_conn|
          expect(conn.execute("select 2")).to be_a(PG::Result)
        end
      end
    end

    it "correctly checks connections in and out" do
      50.times do
        subject.with_connection do |conn|
          expect(conn.execute("select 1")).to be_a(PG::Result)
        end
      end
    end

    it "correctly checks connections in and out in different fibers" do
      50.times.map {
        Fiber.schedule do
          subject.with_connection do |conn|
            expect(conn.execute("select 1")).to be_a(PG::Result)
          end
        end
      }.then { |fibers| Fiber.await(fibers) }
    end
  end

  describe "pool exhaustion and blocking" do
    it "blocks fibers when pool is exhausted and resumes when connection available" do
      pool_size = subject.size

      # Exhaust the pool
      holders = pool_size.times.map do
        Fiber.schedule do
          subject.connection
          sleep 1.0  # Hold connection
          subject.release_connection
        end
      end

      sleep 0.1  # Let holders acquire connections

      # This fiber should block
      blocked_fiber_executed = false
      blocked = Fiber.schedule do
        subject.connection  # Should block here
        blocked_fiber_executed = true
        subject.release_connection
      end

      sleep 0.2
      expect(blocked_fiber_executed).to be_falsey  # Still blocked
      expect(subject.stat[:waiting]).to eq(1)

      Fiber.await(holders + [blocked])
      expect(blocked_fiber_executed).to be_truthy  # Eventually executed
    end

    it "handles multiple blocked fibers waiting for connections" do
      pool_size = subject.size

      # Exhaust the pool
      holders = pool_size.times.map do
        Fiber.schedule do
          subject.connection
          sleep 0.5
          subject.release_connection
        end
      end

      sleep 0.1

      # Create multiple blocked fibers
      execution_order = []
      blocked_fibers = 3.times.map do |i|
        Fiber.schedule do
          subject.connection
          execution_order << i
          subject.release_connection
        end
      end

      Fiber.await(holders + blocked_fibers)
      expect(execution_order.length).to eq(3)
    end
  end

  describe "checkout timeout" do
    it "raises ConnectionTimeoutError when checkout times out" do
      pool_size = subject.size
      checkout_timeout = subject.instance_variable_get(:@__checkout_timeout)

      # Exhaust pool and hold connections longer than timeout
      holders = pool_size.times.map do
        Fiber.schedule do
          subject.connection
          sleep(checkout_timeout + 2)
          subject.release_connection
        end
      end

      sleep 0.1

      expect {
        Fiber.await(Fiber.schedule { subject.connection })
      }.to raise_error(ActiveRecord::ConnectionTimeoutError, /could not obtain a connection/)
    ensure
      Fiber.await(holders) rescue nil
    end
  end

  describe "#release_connection" do
    it "correctly releases connections" do
      20.times.map {
        Fiber.schedule do
          subject.connection
          sleep 0.2
          subject.release_connection
        end
      }.then { |fibers| Fiber.await(fibers) }
    end
  end

  describe "#active_connection?" do
    it "returns false if there is no active connection" do
      expect(subject.active_connection?).to be_falsey
    end

    it "returns true if there is an active connection" do
      subject.connection
      expect(subject.active_connection?).to be_truthy
    ensure
      subject.release_connection
    end

    it "works correctly with with_connection" do
      subject.with_connection do
        expect(subject.active_connection?).to be_truthy

        subject.with_connection do
          expect(subject.active_connection?).to be_truthy
        end
      end

      expect(subject.active_connection?).to be_falsey
    end

    it "doesn't share connections between fibers" do
      subject.connection

      Fiber.await(
        Fiber.schedule { expect(subject.active_connection?).to be_falsey }
      )
    ensure
      subject.release_connection
    end

    it "doesn't share connections between threads" do
      subject.connection

      Thread.new {
        expect(subject.active_connection?).to be_falsey
      }.join
    ensure
      subject.release_connection
    end
  end

  describe "#reap" do
    it "reaps connections from dead fibers" do
      Fiber.schedule do
        subject.connection
        # Fiber exits without releasing
      end

      expect(subject.stat[:dead]).to eq(1)

      subject.reap

      expect(subject.stat[:dead]).to eq(0)
      expect(subject.stat[:idle]).to eq(subject.size)
    end

    it "resets active connections from crashed fibers" do
      fiber = Fiber.schedule do
        conn = subject.connection
        # Simulate work
        conn.execute("select 1")
        # Fiber exits without releasing
      end

      Fiber.await(fiber)

      Fiber.__await_internal_fibers { subject.reap }

      # Connection should be reset and returned to pool
      expect(subject.stat[:idle]).to eq(subject.size)
    end

    it "ignores calls from non-owner threads" do
      fiber = Fiber.schedule do
        subject.connection
        # Fiber exits without releasing
      end

      Thread.new { subject.reap }.join

      expect(subject.stat[:dead]).to eq(1)
    ensure
      subject.release_connection(fiber)
    end

    context "with min_connections" do
      before do
        skip("skipping on Active Record < 8.1") if ActiveRecord.version < Gem::Version.create("8.1")
      end

      let(:db_config) { super().merge(min_connections: 1) }

      it "preconnects connections" do
        Fiber.schedule do
          subject.connection
        end

        subject.reap
        expect(subject.connections.count(&:active?)).to be(0)

        Fiber.pause # wait for `preconnect` to kick in
        ensure_preconnected.call # wait for `preconnect` to finish

        expect(subject.connections.last).to be_active
      end
    end
  end

  describe "#with_connection exception handling" do
    it "releases connection when exception is raised in block" do
      expect {
        subject.with_connection do |conn|
          raise StandardError, "test error"
        end
      }.to raise_error(StandardError, "test error")

      expect(subject.active_connection?).to be_falsey
      expect(subject.stat[:busy]).to eq(0)
    end

    it "releases connection when multiple nested with_connection calls raise" do
      expect {
        subject.with_connection do |conn1|
          subject.with_connection do |conn2|
            raise StandardError, "nested error"
          end
        end
      }.to raise_error(StandardError, "nested error")

      expect(subject.active_connection?).to be_falsey
      expect(subject.stat[:busy]).to eq(0)
    end
  end

  describe "#flush" do
    it "marks idle connections for reconnect after idle timeout" do
      subject.with_connection { |c| c.execute("select 1") }

      idle_timeout = subject.instance_variable_get(:@__idle_timeout)
      skip "idle_timeout not configured" if idle_timeout.nil?

      # Manually set idle_since to simulate passage of time
      subject.connections.each do |conn|
        conn.__idle_since = Process.clock_gettime(Process::CLOCK_MONOTONIC) - idle_timeout - 1
      end

      subject.flush

      # Verify connections were marked for reconnect
      subject.connections.each do |conn|
        expect(conn.__needs_reconnect).to be_truthy
      end
    end

    it "does not affect connections that haven't exceeded idle timeout" do
      subject.with_connection { |c| c.execute("select 1") }

      subject.flush

      # Connections should still be usable
      subject.with_connection do |conn|
        expect(conn.execute("select 1")).to be_a(PG::Result)
      end
    end

    it "flushes connections" do
      skip("skipping on Active Record 7.1") if ActiveRecord.version < Gem::Version.create("7.2")

      fiber = Fiber.schedule do
        subject.with_connection do |conn|
          conn.execute("select 1")
          allow(conn).to receive(:__idle_since).and_return(0)
        end
      end

      Fiber.await(fiber)
      expect(subject.connections.count(&:active?)).to eq(1)

      subject.flush

      expect(subject.connections.count(&:active?)).to eq(0)
    end

    it "ignores calls from non-owner threads" do
      connection = subject.with_connection do |conn|
        conn.execute("select 1")
        allow(conn).to receive(:__idle_since).and_return(0)
        conn
      end

      expect(connection).to be_active

      Thread.new { subject.flush }.join

      # connection is still active - `flush` returned early
      expect(connection).to be_active
    end

    context "with min_connections" do
      before do
        skip("skipping on Active Record < 8.1") if ActiveRecord.version < Gem::Version.create("8.1")
      end

      let(:db_config) { super().merge(min_connections: 1) }

      it "preconnects connections" do
        fiber_1 = Fiber.schedule do
          subject.with_connection do |conn|
            conn.execute("select 1")
            allow(conn).to receive(:__idle_since).and_return(0)
          end
        end

        fiber_2 = Fiber.schedule do
          subject.with_connection do |conn|
            conn.execute("select 1")
            allow(conn).to receive(:__idle_since).and_return(0)
          end
        end

        Fiber.await([fiber_1, fiber_2])
        expect(subject.connections.count { |conn| !conn.active? }).to eq(pool_size - 2)

        subject.flush

        # one connection has been left active
        expect(subject.connections.count { |conn| !conn.active? }).to eq(pool_size - 1)

        # the active one is at the end of the list
        expect(subject.connections.last).to be_active
      end
    end

    context "during disconnect" do
      it "doesn't raise error" do
        subject.connection
        subject.disconnect

        expect { subject.flush }.not_to raise_error

      ensure
        subject.release_connection
      end
    end
  end

  describe "#retire_old_connections" do
    before do
      skip("skipping on Active Record < 8.1") if ActiveRecord.version < Gem::Version.create("8.1")
    end

    it "doesn't disconnect connections when no `max_age` is set" do
      connection = subject.with_connection do |conn|
        conn.execute("select 1")
        conn
      end

      result = subject.retire_old_connections

      expect(result).to be(false)
      expect(connection).to be_active
    end

    context "with `max_age` set" do
      let(:db_config) { super().merge(max_age: 10) }

      it "disconnects old connections" do
        connection = subject.with_connection do |conn|
          conn.execute("select 1")
          allow(conn).to receive(:connection_age).and_return(100)
          conn
        end

        result = subject.retire_old_connections

        expect(result).to be(true)
        expect(connection).not_to be_active
      end

      it "returns false if no connections were disconnected" do
        result = subject.retire_old_connections
        expect(result).to be(false)
      end
    end

    context "during disconnect" do
      it "doesn't raise error" do
        subject.connection
        subject.disconnect

        expect { subject.retire_old_connections }.not_to raise_error

      ensure
        subject.release_connection
      end
    end
  end

  describe "#keep_alive" do
    before do
      skip("skipping on Active Record < 8.1") if ActiveRecord.version < Gem::Version.create("8.1")
    end

    let(:db_config) { super().merge(keepalive: 10) }

    it "ignores fresh connections" do
      subject.connections.each do |conn|
        expect(conn).not_to receive(:disconnect!)
      end

      subject.keep_alive
      expect(subject.connections.length).to eq(pool_size)
    end

    it "pings stale connections" do
      fiber_1 = Fiber.schedule do
        subject.with_connection do |conn|
          allow(conn).to receive(:seconds_since_last_activity).and_return(100)
          conn.execute("select 1")
        end
      end

      fiber_2 = Fiber.schedule do
        subject.with_connection do |conn|
          allow(conn).to receive(:seconds_since_last_activity).and_return(100)
          conn.execute("select 1")
        end
      end

      fiber_3 = Fiber.schedule do
        subject.with_connection do |conn|
          conn.execute("select 1")
        end
      end

      Fiber.await([fiber_1, fiber_2, fiber_3])

      # ensure the last connection on the list is inactive
      subject.connections.last.disconnect!

      # pings from `keep_alive`
      allow(subject.connections[-2]).to receive(:active?).and_call_original
      allow(subject.connections[-3]).to receive(:active?).and_call_original

      Fiber.__await_internal_fibers { subject.keep_alive }

      # ensure active connections are now at the end of the list
      expect(subject.connections.length).to eq(pool_size)
      expect(subject.connections.last(2).all?(&:active?)).to be(true)
    end

    it "disconnects broken connections" do
      connection = subject.with_connection do |conn|
        allow(conn).to receive(:seconds_since_last_activity).and_return(100)
        conn
      end

      expect(subject.connections.last).to eq(connection)

      expect(connection).to receive(:disconnect!)
      Fiber.__await_internal_fibers { subject.keep_alive }

      # broken connection is pushed to the bottom
      expect(subject.connections.first).to eq(connection)
    end

    context "during disconnect" do
      it "doesn't raise error" do
        subject.connection
        subject.disconnect

        expect { subject.keep_alive }.not_to raise_error

      ensure
        subject.release_connection
      end
    end
  end

  describe "#preconnect" do
    before do
      skip("skipping on Active Record < 8.1") if ActiveRecord.version < Gem::Version.create("8.1")
    end

    context "with `min_connections`" do
      let(:db_config) { super().merge(min_connections: 3) }

      it "preconnects connections" do
        subject.preconnect

        expect(subject.connections.length).to eq(pool_size)
        expect(subject.connections.last(3).all?(&:active?)).to be(true)
      end
    end

    context "with `min_connection` bigger than number of connections" do
      let(:db_config) { super().merge(min_connections: 1_000) }

      it "preconnects connections" do
        subject.preconnect

        expect(subject.connections.length).to eq(pool_size)
        expect(subject.connections.all?(&:active?)).to be(true)
      end
    end

    context "with no `min_connections`" do
      it "doesn't preconnect connections" do
        subject.preconnect

        expect(subject.connections.length).to eq(pool_size)
        expect(subject.connections.none?(&:active?)).to be(true)
      end
    end

    context "during disconnect" do
      it "doesn't raise error" do
        subject.connection
        subject.disconnect

        expect { subject.preconnect }.not_to raise_error

      ensure
        subject.release_connection
      end
    end
  end

  describe "#stat" do
    it "accurately tracks pool statistics under concurrent load" do
      10.times.map do
        Fiber.schedule do
          subject.connection
          stats = subject.stat
          expect(stats[:busy]).to be > 0
          expect(stats[:idle]).to be >= 0
          sleep 0.1
          subject.release_connection
        end
      end.then { |fibers| Fiber.await(fibers) }

      final_stats = subject.stat
      expect(final_stats[:busy]).to eq(0)
      expect(final_stats[:idle]).to eq(subject.size)
      expect(final_stats[:waiting]).to eq(0)
    end

    it "tracks waiting fibers correctly" do
      pool_size = subject.size

      # Exhaust the pool
      holders = pool_size.times.map do
        Fiber.schedule do
          subject.connection
          sleep 0.5
          subject.release_connection
        end
      end

      sleep 0.1

      # Create waiting fibers
      waiters = 3.times.map do
        Fiber.schedule do
          subject.connection
          subject.release_connection
        end
      end

      sleep 0.1
      stats = subject.stat
      expect(stats[:waiting]).to be > 0

      Fiber.await(holders + waiters)

      final_stats = subject.stat
      expect(final_stats[:waiting]).to eq(0)
    end
  end

  describe "#disconnect" do
    it "waits for connections to be released before disconnecting" do
      holder = Fiber.schedule do
        subject.connection
        sleep 0.3
        expect(subject.connection.execute("select 1")).to be_a(PG::Result)
        subject.release_connection
      end

      sleep 0.1
      subject.disconnect

      Fiber.await(holder)
    end

    it "creates new connections after disconnect completes" do
      subject.disconnect

      # Pool should have fresh connections
      expect(subject.stat[:idle]).to eq(subject.size)

      subject.with_connection do |conn|
        expect(conn.execute("select 1")).to be_a(PG::Result)
      end
    end
  end

  describe "monitoring" do
    before do
      skip("skipping on Active Record >= 8.1") if ActiveRecord.version >= Gem::Version.create("8.1")
    end

    it "correctly monitors the pool" do
      expect {
        subject.flush
        subject.reap
        subject.keep_alive
        subject.preconnect
        subject.retire_old_connections
      }.not_to raise_error

      expect(subject.connections.length).to eq(pool_size)
    end
  end
end

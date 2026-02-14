# frozen_string_literal: true

require "active_record"

RSpec.describe Rage::Ext::ActiveRecord::ConnectionPool do
  subject { ActiveRecord::Base.connection_pool }

  before :all do
    skip("skipping external tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"

    Fiber.set_scheduler(Rage::FiberScheduler.new)
    ActiveRecord::Base.establish_connection(url: (ENV["TEST_PG_URL"]).to_s)
    ActiveRecord::Base.connection_pool.extend(Rage::Ext::ActiveRecord::ConnectionPool)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  around do |example|
    # we need to init the extension before every test to refresh the subscriptions
    subject.__init_rage_extension

    within_reactor do
      example.call
      -> {}
    end

    # cleanup - remove the connections
    subject.connections.each do |conn|
      conn.disconnect!
      subject.__remove__(conn)
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
      fiber = Fiber.schedule do
        subject.connection
        # Fiber exits without releasing
      end

      Fiber.await(fiber)
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
      subject.reap

      # Connection should be reset and returned to pool
      expect(subject.stat[:idle]).to eq(subject.size)
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
end

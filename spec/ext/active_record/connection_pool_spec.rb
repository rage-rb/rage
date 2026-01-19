# frozen_string_literal: true

require "active_record"

RSpec.describe Rage::Ext::ActiveRecord::ConnectionPool do
  subject { ActiveRecord::Base.connection_pool }

  before :all do
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
    it "returns false if there is an active connection" do
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
end

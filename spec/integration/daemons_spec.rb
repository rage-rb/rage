# frozen_string_literal: true

require "redis-client"

RSpec.describe "Daemons" do
  before :all do
    skip("skipping file server tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  describe "#perform" do
    before :all do
      launch_server(env: { "RAGE_ENV" => "production", "WEB_CONCURRENCY" => "3", "ENABLE_DAEMONS" => "1" })
    end

    after :all do
      stop_server
    end

    let(:redis) { RedisClient.new(url: ENV["TEST_REDIS_URL"]) }
    let(:logs) { File.readlines("spec/integration/test_app/log/production.log") }

    it "starts daemons" do
      redis.pubsub.call("PUBLISH", "daemon:test:channel", "hello, world")
      sleep 1

      daemon_logs = logs.group_by { |line| line.match(/daemon=(\w+)/).to_a.last }

      expect(daemon_logs["RedisListener1"].size).to eq(1)
      expect(daemon_logs["RedisListener1"].last).to include("message=hello, world")

      expect(daemon_logs["RedisListener2"].size).to eq(3)
      daemon_logs["RedisListener2"].each do |line|
        expect(line).to include("message=#{"hello, world".reverse}")
      end
    end

    it "restarts daemons if their processes crash" do
      # kill processes the daemons are attached to
      exclusive_daemon_pid = logs.
        find { |line| line.include?("starting RedisListener1") }.
        match(/\[(\d+)\]/)[1]

      non_exclusive_daemon_pid = logs.
        find { |line| line.include?("starting RedisListener2") }.
        match(/\[(\d+)\]/)[1]

      `kill #{exclusive_daemon_pid}`
      `kill #{non_exclusive_daemon_pid}`

      sleep 1

      # verify they are respawned
      redis.pubsub.call("PUBLISH", "daemon:test:channel", "hello, world")
      sleep 1

      logs = File.readlines("spec/integration/test_app/log/production.log").last(4)
      daemon_logs = logs.group_by { |line| line.match(/daemon=(\w+)/).to_a.last }

      expect(daemon_logs["RedisListener1"].size).to eq(1)
      expect(daemon_logs["RedisListener2"].size).to eq(3)
    end
  end

  describe "#cleanup" do
    before :all do
      launch_server(env: { "RAGE_ENV" => "production", "ENABLE_DAEMONS" => "1" })
    end

    after :all do
      stop_server
    end

    let(:logs) { File.readlines("spec/integration/test_app/log/production.log") }

    it "correctly calls cleanup hooks" do
      Process.kill(:SIGTERM, @test_server_pid)
      sleep 2

      redis_1_log = logs.find { |log| log.match?(/daemon\W+RedisListener1\W+message\W+cleanup done/) }
      redis_2_log = logs.find { |log| log.match?(/daemon\W+RedisListener2\W+message\W+cleanup done/) }
      sleep_log = logs.find { |log| log.match?(/daemon\W+SleepDaemon\W+message\W+cleanup done/) }

      expect(redis_1_log).not_to be_nil
      expect(redis_2_log).not_to be_nil
      expect(sleep_log).not_to be_nil
    end
  end
end

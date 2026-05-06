# frozen_string_literal: true

require "redis-client"

RSpec.describe Rage::PubSub::Adapters::Redis do
  subject { described_class.new(adapter_config) }
  let(:adapter_config) { {} }

  let(:mock_redis) { instance_double(RedisClient) }
  let(:mock_pool) { instance_double(ConnectionPool) }

  before do
    allow(RedisClient).to receive(:config).and_return(double(new_client: mock_redis, new_pool: mock_pool))

    allow(mock_redis).to receive(:call).with("INFO").and_return("redis_version:7.0.5")
    allow(mock_redis).to receive(:close)
  end

  describe "#publish" do
    before do
      allow(mock_pool).to receive(:with).and_yield(mock_redis)
      allow(Rage::Internal).to receive(:pick_a_worker)
    end

    it "adds an entry to the stream" do
      expect(mock_redis).to receive(:call).with(
        "XADD",
        "rage:pubsub:messages",
        "MINID",
        "~",
        instance_of(Integer),
        "*",
        "1",
        "test-stream",
        "2",
        "{\"hello\":\"world\"}",
        "3",
        instance_of(String),
        "4",
        instance_of(String),
        "5",
        "test-broadcaster"
      )

      subject.publish("test-broadcaster", "test-stream", { hello: "world" })
    end

    it "uses the same server UUID" do
      server_uuids = []

      expect(mock_redis).to receive(:call).with(
        "XADD",
        any_args,
        "3",
        satisfy { |server_uuid| server_uuids << server_uuid },
        anything,
        anything,
        anything,
        anything
      ).twice

      subject.publish("test-broadcaster", "test-stream", {})
      subject.publish("test-broadcaster", "test-stream", {})

      expect(server_uuids.uniq.count).to eq(1)
    end

    it "uses different message UUIDs" do
      message_uuids = []

      expect(mock_redis).to receive(:call).with(
        "XADD",
        any_args,
        "4",
        satisfy { |message_uuid| message_uuids << message_uuid },
        anything,
        anything
      ).twice

      subject.publish("test-broadcaster", "test-stream", {})
      subject.publish("test-broadcaster", "test-stream", {})

      expect(message_uuids.uniq.count).to eq(2)
    end

    context "with MAXLEN trimming" do
      before do
        allow(mock_redis).to receive(:call).with("INFO").and_return("redis_version:6.1.0")
      end

      it "adds an entry to the stream" do
        expect(mock_redis).to receive(:call).with(
          "XADD",
          "rage:pubsub:messages",
          "MAXLEN",
          "~",
          "10000",
          "*",
          "1",
          "test-stream",
          "2",
          "{\"hello\":\"world\"}",
          "3",
          instance_of(String),
          "4",
          instance_of(String),
          "5",
          instance_of(String)
        )

        subject.publish("test-broadcaster", "test-stream", { hello: "world" })
      end
    end

    context "with Redis < 6" do
      before do
        allow(mock_redis).to receive(:call).with("INFO").and_return("redis_version:4.0.0")
      end

      it "raises an error" do
        expect { subject }.to raise_error("Redis adapter only supports Redis 6+. Detected Redis version: 4.0.0.")
      end
    end

    context "with channel_prefix" do
      let(:adapter_config) { { channel_prefix: "testing" } }

      it "uses the prefixed stream name" do
        expect(mock_redis).to receive(:call).with(
          "XADD",
          "testing:rage:pubsub:messages",
          any_args
        )

        expect(RedisClient).to receive(:config) do |config|
          expect(config).not_to include(:channel_prefix)
          double(new_client: mock_redis, new_pool: mock_pool)
        end

        subject.publish("test-broadcaster", "test-stream", {})
      end
    end

    context "with custom Redis config" do
      let(:adapter_config) { { db: "3" } }

      it "applies the config" do
        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:pubsub:messages",
          any_args
        )

        expect(RedisClient).to receive(:config) do |config|
          expect(config).to include({
            reconnect_attempts: instance_of(Array),
            db: "3"
          })
          double(new_client: mock_redis, new_pool: mock_pool)
        end

        subject.publish("test-broadcaster", "test-stream", {})
      end
    end

    context "with no config" do
      let(:adapter_config) { {} }

      it "uses the default config" do
        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:pubsub:messages",
          any_args
        )

        expect(RedisClient).to receive(:config) do |config|
          expect(config).to match({ reconnect_attempts: instance_of(Array) })
          double(new_client: mock_redis, new_pool: mock_pool)
        end

        subject.publish("test-broadcaster", "test-stream", {})
      end
    end

    context "with default pool config" do
      it "uses the default values" do
        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:pubsub:messages",
          any_args
        )

        expect(RedisClient.config).to receive(:new_pool).with({ size: 10, timeout: 1 })

        subject.publish("test-broadcaster", "test-stream", {})
      end
    end

    context "with custom pool config" do
      let(:adapter_config) { { pool_size: 100, pool_timeout: 90 } }

      it "uses the custom values" do
        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:pubsub:messages",
          any_args
        )

        expect(RedisClient.config).to receive(:new_pool).with({ size: 100, timeout: 90 })

        subject.publish("test-broadcaster", "test-stream", {})
      end
    end

    context "with no available Redis" do
      it "doesn't raise error" do
        expect(mock_redis).to receive(:call).with("INFO").and_raise(RedisClient::CannotConnectError)
        expect { subject }.to output(/Couldn't connect to Redis/).to_stdout
      end
    end
  end

  describe "#poll" do
    subject do
      described_class.new(adapter_config).add_broadcaster(broadcaster_id, broadcaster)
      poller[0].call
    end

    let(:poller) { [] }
    let(:broadcaster_id) { "test:sse" }
    let(:broadcaster) { double }
    let(:logger) { double }

    before do
      allow(Rage::Internal).to receive(:pick_a_worker) do |&block|
        poller << block
      end

      allow_any_instance_of(described_class).to receive(:sleep)
      allow(Iodine).to receive(:on_state).with(:start_shutdown).and_yield

      allow(logger).to receive(:info?).and_return(false)
      allow(logger).to receive(:error)
      allow(Rage).to receive(:logger).and_return(logger)
    end

    it "read entries from the stream" do
      expect(mock_redis).to receive(:blocking_call).with(
        5,
        "XREAD",
        "COUNT",
        "100",
        "BLOCK",
        "5000",
        "STREAMS",
        "rage:pubsub:messages",
        instance_of(Integer)
      )

      subject
    end

    context "with channel_prefix" do
      let(:adapter_config) { { channel_prefix: "testing" } }

      it "uses the prefixed stream name" do
        expect(mock_redis).to receive(:blocking_call).with(
          5,
          "XREAD",
          "COUNT",
          "100",
          "BLOCK",
          "5000",
          "STREAMS",
          "testing:rage:pubsub:messages",
          instance_of(Integer)
        )

        subject
      end
    end

    it "broadcasts the message" do
      allow(mock_redis).to receive(:blocking_call).and_return(
        {
          "rage:pubsub:messages" => [
            ["id", [
              "1", "test-stream",
              "2", "{\"hello\":\"world\"}",
              "3", "server UUID",
              "4", "message UUID",
              "5", "test:sse"
            ]]
          ]
        }
      )

      expect(broadcaster).to receive(:broadcast).with("test-stream", { "hello" => "world" })

      subject
    end

    context "with unknown broadcaster" do
      it "ignores the message" do
        allow(mock_redis).to receive(:blocking_call).and_return(
          {
            "rage:pubsub:messages" => [
              ["id", [
                "1", "test-stream",
                "2", "{\"hello\":\"world\"}",
                "3", "server UUID",
                "4", "message UUID",
                "5", "test:unknown"
              ]]
            ]
          }
        )

        expect { subject }.not_to raise_error
      end
    end

    it "ignores messages with duplicate message UUIDs" do
      allow(mock_redis).to receive(:blocking_call).and_invoke(
        proc {
          {
            "rage:pubsub:messages" => [
              ["id 1", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "server UUID", "4", "message UUID", "5", "test:sse"]],
              ["id 2", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "server UUID", "4", "message UUID", "5", "test:sse"]]
            ]
          }
        }
      )

      expect(broadcaster).to receive(:broadcast).with("test-stream", { "hello" => "world" }).once

      subject
    end

    it "ignores messages from the same broadcaster" do
      allow(SecureRandom).to receive(:uuid).and_return("server UUID")

      allow(mock_redis).to receive(:blocking_call).and_return(
        {
          "rage:pubsub:messages" => [
            ["id", [
              "1", "test-stream",
              "2", "{\"hello\":\"world\"}",
              "3", "server UUID",
              "4", "message UUID",
              "5", "test:sse"
            ]]
          ]
        }
      )

      expect(broadcaster).not_to receive(:broadcast)

      subject
    end

    it "reports redis subscriber errors" do
      allow(mock_redis).to receive(:blocking_call).and_invoke(
        proc { raise RedisClient::CannotConnectError, "redis down" },
        proc { raise Errno::ECONNRESET }
      )

      expect(Rage::Errors).to receive(:report).with(instance_of(RedisClient::CannotConnectError))

      subject
    end
  end
end

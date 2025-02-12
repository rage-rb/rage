# frozen_string_literal: true

require "redis-client"

RSpec.describe Rage::Cable::Adapters::Redis do
  subject { described_class.new(adapter_config) }
  let(:adapter_config) { {} }

  let(:mock_redis) { instance_double(RedisClient) }

  before do
    allow(RedisClient).to receive(:config).and_return(double(new_client: mock_redis))

    allow(mock_redis).to receive(:call).with("INFO").and_return("redis_version:7.0.5")
    allow(mock_redis).to receive(:close)
  end

  describe "#publish" do
    it "adds an entry to the stream" do
      expect(mock_redis).to receive(:call).with(
        "XADD",
        "rage:cable:messages",
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
        instance_of(String)
      )

      subject.publish("test-stream", { hello: "world" })
    end

    it "uses the same server UUID" do
      server_uuids = []

      expect(mock_redis).to receive(:call).with(
        "XADD",
        any_args,
        "3",
        satisfy { |server_uuid| server_uuids << server_uuid },
        anything,
        anything
      ).twice

      subject.publish("test-stream", {})
      subject.publish("test-stream", {})

      expect(server_uuids.uniq.count).to eq(1)
    end

    it "uses different message UUIDs" do
      message_uuids = []

      expect(mock_redis).to receive(:call).with(
        "XADD",
        any_args,
        "4",
        satisfy { |message_uuid| message_uuids << message_uuid }
      ).twice

      subject.publish("test-stream", {})
      subject.publish("test-stream", {})

      expect(message_uuids.uniq.count).to eq(2)
    end

    context "with MAXLEN trimming" do
      before do
        allow(mock_redis).to receive(:call).with("INFO").and_return("redis_version:6.1.0")
      end

      it "adds an entry to the stream" do
        expect(mock_redis).to receive(:call).with(
          "XADD",
          "rage:cable:messages",
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
          instance_of(String)
        )

        subject.publish("test-stream", { hello: "world" })
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
        expect(RedisClient).to receive(:config) do |config|
          expect(config).not_to include(:channel_prefix)
          double(new_client: mock_redis)
        end

        expect(mock_redis).to receive(:call).with(
          "XADD",
          "testing:rage:cable:messages",
          any_args
        )

        subject.publish("test-stream", {})
      end
    end

    context "with custom Redis config" do
      let(:adapter_config) { { db: "3" } }

      it "applies the config" do
        expect(RedisClient).to receive(:config) do |config|
          expect(config).to include({
            reconnect_attempts: instance_of(Array),
            db: "3"
          })
          double(new_client: mock_redis)
        end

        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:cable:messages",
          any_args
        )

        subject.publish("test-stream", {})
      end
    end

    context "with no config" do
      let(:adapter_config) { {} }

      it "uses the default config" do
        expect(RedisClient).to receive(:config) do |config|
          expect(config).to match({ reconnect_attempts: instance_of(Array) })
          double(new_client: mock_redis)
        end

        allow(mock_redis).to receive(:call).with(
          "XADD",
          "rage:cable:messages",
          any_args
        )

        subject.publish("test-stream", {})
      end
    end

    context "with no available Redis" do
      it "doesn't raise error" do
        expect(mock_redis).to receive(:call).with("INFO").and_raise(RedisClient::CannotConnectError)

        allow(STDOUT).to receive(:puts).and_call_original
        expect(STDOUT).to receive(:puts).with(/Couldn't connect to Redis/)

        expect { subject }.not_to raise_error
      end
    end
  end

  describe "#poll" do
    before do
      allow_any_instance_of(described_class).to receive(:pick_a_worker).and_yield
      allow(Iodine).to receive(:on_state).with(:start_shutdown).and_yield
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
        "rage:cable:messages",
        instance_of(Integer)
      ).and_raise

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
          "testing:rage:cable:messages",
          instance_of(Integer)
        ).and_raise

        subject
      end
    end

    it "broadcasts the message" do
      allow(mock_redis).to receive(:blocking_call).and_invoke(
        proc { { "rage:cable:messages" => [["id", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "broadcaster UUID", "4", "message UUID"]]] } },
        proc { raise }
      )

      expect(Rage.config.cable.protocol).to receive(:broadcast).with(
        "test-stream", { "hello" => "world" }
      ).once

      subject
    end

    it "ignores messages with duplicate message UUIDs" do
      allow(mock_redis).to receive(:blocking_call).and_invoke(
        proc {
          { "rage:cable:messages" => [
            ["id 1", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "broadcaster UUID", "4", "message UUID"]],
            ["id 2", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "broadcaster UUID", "4", "message UUID"]]
          ] }
        },
        proc { raise }
      )

      expect(Rage.config.cable.protocol).to receive(:broadcast).with(
        "test-stream", { "hello" => "world" }
      ).once

      subject
    end

    it "ignores messages from the same broadcaster" do
      allow(SecureRandom).to receive(:uuid).and_return("broadcaster UUID")

      allow(mock_redis).to receive(:blocking_call).and_invoke(
        proc { { "rage:cable:messages" => [["id", ["1", "test-stream", "2", "{\"hello\":\"world\"}", "3", "broadcaster UUID", "4", "message UUID"]]] } },
        proc { raise }
      )

      expect(Rage.config.cable.protocol).not_to receive(:broadcast)

      subject
    end
  end
end

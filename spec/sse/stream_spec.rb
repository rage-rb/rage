# frozen_string_literal: true

RSpec.describe Rage::SSE::Stream do
  before do
    described_class.__message_buffer.clear
  end

  describe "#initialize" do
    let(:stream_name) { "my stream" }

    it "sets name" do
      expect(Rage::Internal).to receive(:stream_name_for).with(stream_name).and_return("test-stream-name")

      stream = described_class.new(streamable: stream_name)
      expect(stream.name).to eq("test-stream-name")
    end

    it "sets owner to the current fiber" do
      stream = described_class.new(streamable: stream_name)
      expect(stream.owner).to eq(Fiber.current)
    end

    it "registers the stream in the message buffer" do
      stream = described_class.new(streamable: stream_name)
      expect(described_class.__message_buffer[stream_name]).to have_key(stream.owner)
    end

    it "initializes the buffer with a frozen empty array" do
      stream = described_class.new(streamable: stream_name)
      buffer = described_class.__message_buffer[stream_name][stream.owner]

      expect(buffer).to eq([])
      expect(buffer).to be_frozen
    end

    it "does not overwrite existing buffer for the same owner" do
      stream1 = described_class.new(streamable: stream_name)
      described_class.__store_message(stream_name, "message1")

      # Creating another stream with same name and same owner
      stream2 = described_class.new(streamable: stream_name)

      # Both streams have the same owner, so they share the buffer
      expect(stream1.owner).to eq(stream2.owner)
      expect(described_class.__message_buffer[stream_name][stream1.owner]).to eq(["message1"])
    end

    it "creates separate buffers for different owners" do
      stream1 = nil
      stream2 = nil

      fiber1 = Fiber.new do
        stream1 = described_class.new(streamable: stream_name)
        Fiber.yield
      end
      fiber1.resume

      fiber2 = Fiber.new do
        stream2 = described_class.new(streamable: stream_name)
        Fiber.yield
      end
      fiber2.resume

      # Each fiber has its own buffer entry
      expect(stream1.owner).not_to eq(stream2.owner)
      expect(described_class.__message_buffer[stream_name].keys.count).to eq(2)
    end
  end

  describe ".__store_message" do
    let(:stream_name) { "my stream" }

    it "stores a message for all connections of a stream" do
      stream1 = described_class.new(streamable: stream_name)
      stream2 = described_class.new(streamable: stream_name)

      described_class.__store_message(stream_name, "hello")

      expect(described_class.__message_buffer[stream_name][stream1.owner]).to eq(["hello"])
      expect(described_class.__message_buffer[stream_name][stream2.owner]).to eq(["hello"])
    end

    it "appends messages to existing buffer" do
      stream = described_class.new(streamable: stream_name)

      described_class.__store_message(stream_name, "msg1")
      described_class.__store_message(stream_name, "msg2")
      described_class.__store_message(stream_name, "msg3")

      expect(described_class.__message_buffer[stream_name][stream.owner]).to eq(["msg1", "msg2", "msg3"])
    end
  end

  describe ".__claim_buffered_messages" do
    let(:stream_name) { "my stream" }

    it "returns buffered messages for the stream" do
      stream = described_class.new(streamable: stream_name)
      described_class.__store_message(stream_name, "msg1")
      described_class.__store_message(stream_name, "msg2")

      messages = described_class.__claim_buffered_messages(stream)

      expect(messages).to eq(["msg1", "msg2"])
    end

    it "returns nil when no messages are buffered" do
      stream = described_class.new(streamable: stream_name)

      messages = described_class.__claim_buffered_messages(stream)

      expect(messages).to eq([])
    end

    it "does not clean up streams that have at least one live owner" do
      dead_fiber = Fiber.new do
        described_class.new(streamable: stream_name)
      end
      dead_fiber.resume

      expect(dead_fiber.alive?).to be(false)

      live_stream = described_class.new(streamable: stream_name)
      described_class.__store_message(stream_name, "msg")

      expect(described_class.__message_buffer[stream_name].keys.count).to eq(2)

      # Trigger cleanup
      described_class.__claim_buffered_messages(live_stream)

      # Stream is not removed because at least one fiber is alive
      expect(described_class.__message_buffer).to have_key(stream_name)
    end

    it "removes stream entries when all fibers are dead" do
      dead_fiber = Fiber.new do
        described_class.new(streamable: "dead-stream")
      end
      dead_fiber.resume

      expect(dead_fiber.alive?).to be(false)

      described_class.__store_message("dead-stream", "msg")
      expect(described_class.__message_buffer).to have_key("dead-stream")

      # Trigger cleanup
      live_stream = described_class.new(streamable: "live-stream")
      described_class.__claim_buffered_messages(live_stream)

      # The dead stream should be removed
      expect(described_class.__message_buffer).to_not have_key("dead-stream")
    end
  end
end

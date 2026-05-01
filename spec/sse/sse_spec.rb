# frozen_string_literal: true

RSpec.describe Rage::SSE do
  describe ".message" do
    it "creates a Message with all fields" do
      message = described_class.message("hello", id: "1", event: "update", retry: 3000)

      expect(message).to be_a(Rage::SSE::Message)
      expect(message.data).to eq("hello")
      expect(message.id).to eq("1")
      expect(message.event).to eq("update")
      expect(message.retry).to eq(3000)
    end

    it "creates a Message with only data" do
      message = described_class.message("hello")

      expect(message.data).to eq("hello")
      expect(message.id).to be_nil
      expect(message.event).to be_nil
      expect(message.retry).to be_nil
    end
  end

  describe ".stream" do
    it "creates a Stream" do
      stream = Rage::SSE.stream("my-stream")

      expect(stream).to be_a(Rage::SSE::Stream)
      expect(stream.name).to eq("my-stream")
      expect(stream.owner).to eq(Fiber.current)
    end
  end

  describe ".__serialize" do
    context "with string data" do
      it "wraps in data field" do
        result = described_class.__serialize("hello")
        expect(result).to eq("data: hello\n\n")
      end

      it "handles multiline data in messages" do
        result = described_class.__serialize("line1\nline2")
        expect(result).to eq("data: line1\ndata: line2\n\n")
      end

      it "ignores escaped new line characters" do
        result = described_class.__serialize({ message: "hel\nlo" }.to_json)
        expect(result).to eq("data: {\"message\":\"hel\\nlo\"}\n\n")
      end
    end

    context "with Message data" do
      it "calls to_s on the message" do
        message = Rage::SSE::Message.new(data: "hello", id: "1")
        result = described_class.__serialize(message)
        expect(result).to eq("data: hello\nid: 1\n\n")
      end

      it "handles multiline data in messages" do
        message = Rage::SSE::Message.new(data: "line1\nline2", event: "multi")
        result = described_class.__serialize(message)
        expect(result).to eq("data: line1\ndata: line2\nevent: multi\n\n")
      end
    end

    context "with object data" do
      it "serializes hash as JSON" do
        result = described_class.__serialize({ name: "test", count: 42 })
        expect(result).to eq("data: {\"name\":\"test\",\"count\":42}\n\n")
      end

      it "serializes array as JSON" do
        result = described_class.__serialize([1, 2, 3])
        expect(result).to eq("data: [1,2,3]\n\n")
      end

      it "serializes numbers" do
        result = described_class.__serialize(42)
        expect(result).to eq("data: 42\n\n")
      end

      it "serializes booleans" do
        expect(described_class.__serialize(true)).to eq("data: true\n\n")
        expect(described_class.__serialize(false)).to eq("data: false\n\n")
      end
    end
  end

  describe ".close_stream" do
    before do
      Rage::SSE.__adapter = mock_adapter
    end

    after do
      Rage::SSE.__adapter = nil
    end

    let(:mock_adapter) { double }
    let(:streamable) { [:test_stream, 123] }

    context "inside the runtime" do
      before do
        allow(Iodine).to receive(:running?).and_return(true)
      end

      it "broadcasts the close message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")

        expect(Rage::SSE::InternalBroadcast).to receive(:broadcast).with("test-stream-123", Rage::SSE::CLOSE_STREAM_MSG, Iodine::PubSub::CLUSTER)
        expect(mock_adapter).to receive(:publish).with(Rage::SSE::PUBSUB_BROADCASTER_ID, "test-stream-123", Rage::SSE::CLOSE_STREAM_MSG)

        described_class.close_stream(streamable)
      end
    end

    context "outside the runtime" do
      before do
        allow(Iodine).to receive(:running?).and_return(false)
      end

      it "broadcasts the close message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")

        expect(Rage::SSE::InternalBroadcast).not_to receive(:broadcast)
        expect(mock_adapter).to receive(:publish).with(Rage::SSE::PUBSUB_BROADCASTER_ID, "test-stream-123", Rage::SSE::CLOSE_STREAM_MSG)

        described_class.close_stream(streamable)
      end
    end

    context "without the adapter" do
      before do
        allow(Iodine).to receive(:running?).and_return(true)
      end

      let(:mock_adapter) { nil }

      it "broadcasts the close message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")
        expect(Rage::SSE::InternalBroadcast).to receive(:broadcast).with("test-stream-123", Rage::SSE::CLOSE_STREAM_MSG, Iodine::PubSub::CLUSTER)

        expect { described_class.close_stream(streamable) }.not_to raise_error
      end
    end
  end

  describe ".broadcast" do
    before do
      Rage::SSE.__adapter = mock_adapter
    end

    after do
      Rage::SSE.__adapter = nil
    end

    let(:mock_adapter) { double }
    let(:streamable) { [:test_stream, 123] }

    let(:message) { "message" }
    let(:serialized_message) { "serialized-message" }

    context "inside the runtime" do
      before do
        allow(Iodine).to receive(:running?).and_return(true)
      end

      it "broadcasts the message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")
        allow(Rage::SSE).to receive(:__serialize).with(message).and_return(serialized_message)

        expect(Rage::SSE::InternalBroadcast).to receive(:broadcast).with("test-stream-123", serialized_message, Iodine::PubSub::CLUSTER)
        expect(mock_adapter).to receive(:publish).with(Rage::SSE::PUBSUB_BROADCASTER_ID, "test-stream-123", serialized_message)

        described_class.broadcast(streamable, message)
      end
    end

    context "outside the runtime" do
      before do
        allow(Iodine).to receive(:running?).and_return(false)
      end

      it "broadcasts the message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")
        allow(Rage::SSE).to receive(:__serialize).with(message).and_return(serialized_message)

        expect(Rage::SSE::InternalBroadcast).not_to receive(:broadcast)
        expect(mock_adapter).to receive(:publish).with(Rage::SSE::PUBSUB_BROADCASTER_ID, "test-stream-123", serialized_message)

        described_class.broadcast(streamable, message)
      end
    end

    context "without the adapter" do
      before do
        allow(Iodine).to receive(:running?).and_return(true)
      end

      let(:mock_adapter) { nil }

      it "broadcasts the message" do
        allow(Rage::Internal).to receive(:stream_name_for).with(streamable).and_return("test-stream-123")
        allow(Rage::SSE).to receive(:__serialize).with(message).and_return(serialized_message)

        expect(Rage::SSE::InternalBroadcast).to receive(:broadcast).with("test-stream-123", serialized_message, Iodine::PubSub::CLUSTER)

        described_class.broadcast(streamable, message)
      end
    end
  end

  describe "InternalBroadcast.broadcast" do
    subject { Rage::SSE::InternalBroadcast.broadcast(stream_name, data, engine) }

    let(:stream_name) { "test-stream" }
    let(:data) { double }
    let(:engine) { double }

    before do
      Rage::SSE::Stream.__message_buffer.clear
    end

    it "publishes the message" do
      expect(Iodine).to receive(:publish).with("sse:test-stream", data, engine)
      subject
    end

    it "doesn't attempt to store a message" do
      allow(Iodine).to receive(:publish)
      subject
      expect(Rage::SSE::Stream.__message_buffer).to be_empty
    end

    context "with an existing stream" do
      before do
        Rage::SSE::Stream.__message_buffer.clear
        Rage::SSE.stream("test-stream")
      end

      after do
        Rage::SSE::Stream.__message_buffer.clear
      end

      it "stores a message" do
        allow(Iodine).to receive(:publish)
        subject
        expect(Rage::SSE::Stream.__message_buffer).to have_key("test-stream")
      end
    end
  end
end

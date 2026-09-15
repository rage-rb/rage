# frozen_string_literal: true

RSpec.describe Rage::PubSub do
  before do
    allow(Iodine).to receive(:subscribe)
    allow(Iodine).to receive(:unsubscribe)
    allow(Iodine).to receive(:subscribed?).and_return(false)
    allow(Iodine).to receive(:publish)
    allow(Iodine).to receive(:running?).and_return(true)
    allow(Iodine).to receive(:on_state)

    # Reset subscriptions between tests
    described_class.send(:subscriptions).clear
  end

  describe ".subscribe" do
    it "registers a subscription" do
      callback = proc { |msg| msg }
      result = described_class.subscribe(topic: "orders", subscription_id: :listener, &callback)

      expect(result).to be(true)
    end

    it "subscribes to Iodine with the serialized topic" do
      expect(Iodine).to receive(:subscribe).with("pubsub:orders")

      described_class.subscribe(topic: "orders", subscription_id: :listener) { |msg| msg }
    end

    it "only subscribes to Iodine once per topic" do
      allow(Iodine).to receive(:subscribed?).and_return(false, true)
      expect(Iodine).to receive(:subscribe).once

      described_class.subscribe(topic: "orders", subscription_id: :first) { |msg| msg }
      described_class.subscribe(topic: "orders", subscription_id: :second) { |msg| msg }
    end

    it "raises an error when subscription already exists" do
      described_class.subscribe(topic: "orders", subscription_id: :listener) { |msg| msg }

      expect {
        described_class.subscribe(topic: "orders", subscription_id: :listener) { |msg| msg }
      }.to raise_error(ArgumentError, /topic "orders".*subscription_id :listener.*already exists/)
    end

    it "allows different subscription_ids for the same topic" do
      expect {
        described_class.subscribe(topic: "orders", subscription_id: :first) { |msg| msg }
        described_class.subscribe(topic: "orders", subscription_id: :second) { |msg| msg }
      }.not_to raise_error
    end

    it "allows the same subscription_id for different topics" do
      expect {
        described_class.subscribe(topic: "orders", subscription_id: :listener) { |msg| msg }
        described_class.subscribe(topic: "users", subscription_id: :listener) { |msg| msg }
      }.not_to raise_error
    end

    context "with object topics" do
      it "handles objects responding to id" do
        user = double("User", id: 123, class: double(name: "User"))
        expect(Iodine).to receive(:subscribe).with("pubsub:User:123")

        described_class.subscribe(topic: user, subscription_id: :listener) { |msg| msg }
      end

      it "handles array topics" do
        user = double("User", id: 42, class: double(name: "User"))
        expect(Iodine).to receive(:subscribe).with("pubsub:User:42:notifications")

        described_class.subscribe(topic: [user, "notifications"], subscription_id: :listener) { |msg| msg }
      end
    end
  end

  describe ".unsubscribe" do
    before do
      described_class.subscribe(topic: "orders", subscription_id: :listener) { |msg| msg }
    end

    it "removes the subscription" do
      result = described_class.unsubscribe(topic: "orders", subscription_id: :listener)

      expect(result).to be(true)
    end

    it "raises an error when topic does not exist" do
      expect {
        described_class.unsubscribe(topic: "unknown", subscription_id: :listener)
      }.to raise_error(ArgumentError, /No subscription found with topic "unknown" and subscription_id :listener/)
    end

    it "raises an error when subscription_id does not exist" do
      expect {
        described_class.unsubscribe(topic: "orders", subscription_id: :unknown)
      }.to raise_error(ArgumentError, /No subscription found with topic "orders" and subscription_id :unknown/)
    end

    it "allows unsubscribing one subscription while keeping others" do
      described_class.subscribe(topic: "orders", subscription_id: :second) { |msg| msg }

      described_class.unsubscribe(topic: "orders", subscription_id: :listener)

      expect {
        described_class.unsubscribe(topic: "orders", subscription_id: :second)
      }.not_to raise_error
    end
  end

  describe ".publish" do
    it "publishes the message" do
      expect(Iodine).to receive(:publish).with("pubsub:orders", "test message")

      result = described_class.publish("test message", topic: "orders")

      expect(result).to be(true)
    end

    it "raises an error when message is not a string" do
      expect {
        described_class.publish({ data: "test" }, topic: "orders")
      }.to raise_error(ArgumentError, /Message must be a String, got Hash/)
    end

    it "raises an error for nil message" do
      expect {
        described_class.publish(nil, topic: "orders")
      }.to raise_error(ArgumentError, /Message must be a String, got NilClass/)
    end

    it "raises an error for symbol message" do
      expect {
        described_class.publish(:test, topic: "orders")
      }.to raise_error(ArgumentError, /Message must be a String, got Symbol/)
    end

    it "does not publish to Iodine when not running" do
      allow(Iodine).to receive(:running?).and_return(false)
      expect(Iodine).not_to receive(:publish)

      described_class.publish("test", topic: "orders")
    end

    context "with object topics" do
      it "serializes topics correctly" do
        user = double("User", id: 99, class: double(name: "User"))
        expect(Iodine).to receive(:publish).with("pubsub:User:99", "hello")

        described_class.publish("hello", topic: user)
      end

      it "serializes array topics correctly" do
        expect(Iodine).to receive(:publish).with("pubsub:room:123:chat", "hello")

        described_class.publish("hello", topic: ["room", 123, "chat"])
      end
    end

    context "with adapter configured" do
      let(:mock_adapter) { double("Adapter") }

      before do
        described_class.instance_variable_set(:@__adapter, mock_adapter)
      end

      after do
        described_class.instance_variable_set(:@__adapter, nil)
      end

      it "publishes to both Iodine and the adapter" do
        expect(Iodine).to receive(:publish).with("pubsub:orders", "test")
        expect(mock_adapter).to receive(:publish).with("pubsub", "pubsub:orders", "test")

        described_class.publish("test", topic: "orders")
      end
    end
  end

  describe "message delivery" do
    it "invokes the callback when a message is received" do
      received_messages = []
      iodine_callback = nil

      allow(Iodine).to receive(:subscribe) do |_channel, &block|
        iodine_callback = block
      end

      described_class.subscribe(topic: "orders", subscription_id: :listener) do |message|
        received_messages << message
      end

      iodine_callback.call("pubsub:orders", "order created")

      expect(received_messages).to eq(["order created"])
    end

    it "invokes all callbacks for a topic" do
      messages_a = []
      messages_b = []
      iodine_callback = nil

      allow(Iodine).to receive(:subscribe) do |_channel, &block|
        iodine_callback = block
      end
      allow(Iodine).to receive(:subscribed?).and_return(false, true)

      described_class.subscribe(topic: "orders", subscription_id: :a) { |msg| messages_a << msg }
      described_class.subscribe(topic: "orders", subscription_id: :b) { |msg| messages_b << msg }

      iodine_callback.call("pubsub:orders", "new order")

      expect(messages_a).to eq(["new order"])
      expect(messages_b).to eq(["new order"])
    end

    it "logs errors from callbacks without stopping other callbacks" do
      messages = []
      iodine_callback = nil
      logger = double("Logger")
      allow(logger).to receive(:error)

      allow(Iodine).to receive(:subscribe) do |_channel, &block|
        iodine_callback = block
      end
      allow(Iodine).to receive(:subscribed?).and_return(false, true)

      allow(Rage).to receive(:logger).and_return(logger)

      described_class.subscribe(topic: "orders", subscription_id: :failing) do |_msg|
        raise "callback error"
      end
      described_class.subscribe(topic: "orders", subscription_id: :working) do |msg|
        messages << msg
      end

      iodine_callback.call("pubsub:orders", "test")

      expect(logger).to have_received(:error).with(/PubSub callback failed.*callback error/, anything)
      expect(messages).to eq(["test"])
    end
  end
end

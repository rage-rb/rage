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

  describe ".__serialize" do
    context "with string data" do
      it "wraps in data field" do
        result = described_class.__serialize("hello")
        expect(result).to eq("data: hello\n\n")
      end

      it "does not split multiline strings" do
        result = described_class.__serialize("line1\nline2")
        expect(result).to eq("data: line1\nline2\n\n")
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
end

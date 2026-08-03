# frozen_string_literal: true

RSpec.describe Rage::SSE::Message do
  describe "#to_s" do
    context "with data only" do
      it "formats simple string data" do
        message = described_class.new(data: "hello")
        expect(message.to_s).to eq("data: hello\n\n")
      end

      it "formats multiline string data" do
        message = described_class.new(data: "line1\nline2\nline3")
        expect(message.to_s).to eq("data: line1\ndata: line2\ndata: line3\n\n")
      end

      it "formats object data as JSON" do
        message = described_class.new(data: { name: "test", count: 42 })
        expect(message.to_s).to eq("data: {\"name\":\"test\",\"count\":42}\n\n")
      end

      it "formats array data as JSON" do
        message = described_class.new(data: [1, 2, 3])
        expect(message.to_s).to eq("data: [1,2,3]\n\n")
      end
    end

    context "with id" do
      it "includes the id field" do
        message = described_class.new(data: "hello", id: "123")
        expect(message.to_s).to eq("data: hello\nid: 123\n\n")
      end

      it "excludes id when nil" do
        message = described_class.new(data: "hello", id: nil)
        expect(message.to_s).to eq("data: hello\n\n")
      end
    end

    context "with event" do
      it "includes the event field" do
        message = described_class.new(data: "hello", event: "update")
        expect(message.to_s).to eq("data: hello\nevent: update\n\n")
      end

      it "excludes event when nil" do
        message = described_class.new(data: "hello", event: nil)
        expect(message.to_s).to eq("data: hello\n\n")
      end
    end

    context "with retry" do
      it "includes the retry field for positive values" do
        message = described_class.new(data: "hello", retry: 3000)
        expect(message.to_s).to eq("data: hello\nretry: 3000\n\n")
      end

      it "excludes retry when zero" do
        message = described_class.new(data: "hello", retry: 0)
        expect(message.to_s).to eq("data: hello\n\n")
      end

      it "excludes retry when negative" do
        message = described_class.new(data: "hello", retry: -1000)
        expect(message.to_s).to eq("data: hello\n\n")
      end

      it "excludes retry when nil" do
        message = described_class.new(data: "hello", retry: nil)
        expect(message.to_s).to eq("data: hello\n\n")
      end

      it "converts float retry to integer" do
        message = described_class.new(data: "hello", retry: 2500.7)
        expect(message.to_s).to eq("data: hello\nretry: 2500\n\n")
      end
    end

    context "with all fields" do
      it "includes all fields in the correct order" do
        message = described_class.new(data: "hello", id: "456", event: "message", retry: 5000)
        expect(message.to_s).to eq("data: hello\nid: 456\nevent: message\nretry: 5000\n\n")
      end

      it "handles multiline data with all fields" do
        message = described_class.new(data: "line1\nline2", id: "789", event: "multi", retry: 1000)
        expect(message.to_s).to eq("data: line1\ndata: line2\nid: 789\nevent: multi\nretry: 1000\n\n")
      end

      it "handles JSON data with all fields" do
        message = described_class.new(data: { status: "ok" }, id: "1", event: "status", retry: 2000)
        expect(message.to_s).to eq("data: {\"status\":\"ok\"}\nid: 1\nevent: status\nretry: 2000\n\n")
      end
    end
  end

  describe "attributes" do
    it "supports keyword initialization" do
      message = described_class.new(id: "1", event: "test", retry: 1000, data: "hello")
      expect(message.id).to eq("1")
      expect(message.event).to eq("test")
      expect(message.retry).to eq(1000)
      expect(message.data).to eq("hello")
    end

    it "allows attribute assignment" do
      message = described_class.new
      message.id = "2"
      message.event = "update"
      message.retry = 500
      message.data = "world"

      expect(message.id).to eq("2")
      expect(message.event).to eq("update")
      expect(message.retry).to eq(500)
      expect(message.data).to eq("world")
    end
  end
end

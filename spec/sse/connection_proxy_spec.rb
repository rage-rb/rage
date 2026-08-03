# frozen_string_literal: true

RSpec.describe Rage::SSE::ConnectionProxy do
  let(:connection) { MockConnection.new }
  let(:proxy) { described_class.new(connection) }

  # Minimal mock that mirrors Iodine's connection interface
  class MockConnection
    attr_reader :messages

    def initialize(open: true)
      @messages = []
      @open = open
    end

    def write(data)
      @messages << data
      true
    end

    def close
      @open = false
      true
    end

    def open?
      @open
    end
  end

  describe "#write" do
    it "writes data to the connection" do
      proxy.write("data: hello\n\n")
      expect(connection.messages).to eq(["data: hello\n\n"])
    end

    it "converts data to string" do
      proxy.write(42)
      expect(connection.messages).to eq(["42"])
    end

    it "writes multiple times" do
      proxy.write("first")
      proxy.write("second")
      expect(connection.messages).to eq(["first", "second"])
    end

    it "raises IOError when connection is closed" do
      connection.close
      expect { proxy.write("data") }.to raise_error(IOError, "closed stream")
    end
  end

  describe "#<<" do
    it "writes data to the connection" do
      proxy << "data: hello\n\n"
      expect(connection.messages).to eq(["data: hello\n\n"])
    end

    it "converts data to string" do
      proxy << 42
      expect(connection.messages).to eq(["42"])
    end

    it "raises IOError when connection is closed" do
      connection.close
      expect { proxy << "data" }.to raise_error(IOError, "closed stream")
    end
  end

  describe "#close" do
    it "closes the connection" do
      proxy.close
      expect(proxy.closed?).to be true
    end
  end

  describe "#close_write" do
    it "closes the connection" do
      proxy.close_write
      expect(proxy.closed?).to be true
    end
  end

  describe "#closed?" do
    it "returns false when connection is open" do
      expect(proxy.closed?).to be false
    end

    it "returns true when connection is closed" do
      connection.close
      expect(proxy.closed?).to be true
    end
  end

  describe "#flush" do
    it "does not raise when connection is open" do
      expect { proxy.flush }.not_to raise_error
    end

    it "raises IOError when connection is closed" do
      connection.close
      expect { proxy.flush }.to raise_error(IOError, "closed stream")
    end
  end

  describe "#read" do
    it "is a no-op" do
      expect(proxy.read).to be_nil
    end
  end

  describe "#close_read" do
    it "is a no-op" do
      expect(proxy.close_read).to be_nil
    end
  end
end

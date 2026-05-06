# frozen_string_literal: true

RSpec.describe Rage::SSE::Application do
  let(:connection) { MockSSEConnection.new }

  class MockSSEConnection
    attr_reader :messages

    def initialize
      @messages = []
      @open = true
    end

    def write(data)
      @messages << data
    end

    def close
      @open = false
    end

    def open?
      @open
    end
  end

  before do
    allow(Iodine).to receive(:task_inc!)
    allow(Iodine).to receive(:task_dec!)
    allow(Fiber).to receive(:schedule) { |&block| block.call }
  end

  describe "#start_stream graceful shutdown" do
    it "increments and decrements iodine task counter for enumerator streams" do
      stream = [1, 2, 3].each

      expect(Iodine).to receive(:task_inc!).ordered
      expect(Iodine).to receive(:task_dec!).ordered

      app = described_class.new(stream)
      app.on_open(connection)
    end

    it "increments and decrements iodine task counter for proc streams" do
      stream = ->(conn) { conn.write("data: hello\n\n"); conn.close }

      expect(Iodine).to receive(:task_inc!).ordered
      expect(Iodine).to receive(:task_dec!).ordered

      app = described_class.new(stream)
      app.on_open(connection)
    end

    it "decrements iodine task counter even when stream raises" do
      stream = ->(_conn) { raise "boom" }
      logger = double("logger")
      allow(Rage).to receive(:logger).and_return(logger)
      allow(logger).to receive(:error)
      allow(Rage::Errors).to receive(:report)

      expect(Iodine).to receive(:task_inc!)
      expect(Iodine).to receive(:task_dec!)

      app = described_class.new(stream)
      app.on_open(connection)

      expect(Rage::Errors).to have_received(:report).with(instance_of(RuntimeError))
    end
  end

  describe "#start_raw_stream" do
    it "closes the connection when the proc raises an exception" do
      failing_proc = ->(conn) {
        conn.write("data: before error\n\n")
        raise "boom"
      }

      app = described_class.new(failing_proc)

      expect {
        app.send(:start_raw_stream, connection)
      }.to raise_error(RuntimeError, "boom")

      expect(connection.open?).to be false
    end

    it "does not close the connection on normal completion" do
      async_proc = ->(conn) {
        conn.write("data: started\n\n")
        # Proc returns without closing — a background fiber will close later
      }

      app = described_class.new(async_proc)
      app.send(:start_raw_stream, connection)

      expect(connection.open?).to be true
    end

    it "does not interfere when the proc closes the connection itself" do
      well_behaved_proc = ->(conn) {
        conn.write("data: hello\n\n")
        conn.close
      }

      app = described_class.new(well_behaved_proc)
      app.send(:start_raw_stream, connection)

      expect(connection.open?).to be false
      expect(connection.messages).to eq(["data: hello\n\n"])
    end
  end

  describe "#send_data (single-value streams)" do
    it "writes serialized data and closes the connection" do
      allow(Rage::SSE).to receive(:__serialize).with("hello").and_return("data: hello\n\n")

      app = described_class.new("hello")
      app.on_open(connection)

      expect(connection.messages).to eq(["data: hello\n\n"])
      expect(connection.open?).to be false
    end

    it "closes the connection even when serialization raises" do
      stream = double("stream")
      allow(Rage::SSE).to receive(:__serialize).with(stream).and_raise(RuntimeError, "serialization failed")

      app = described_class.new(stream)

      expect {
        app.on_open(connection)
      }.to raise_error(RuntimeError, "serialization failed")

      expect(connection.open?).to be false
    end

    it "closes the connection even when write raises" do
      allow(Rage::SSE).to receive(:__serialize).with("hello").and_return("data: hello\n\n")
      allow(connection).to receive(:write).and_raise(IOError, "write failed")

      app = described_class.new("hello")

      expect {
        app.on_open(connection)
      }.to raise_error(IOError, "write failed")

      expect(connection.open?).to be false
    end
  end

  describe "log context propagation across fiber boundaries" do
    before do
      allow(Fiber).to receive(:schedule).and_yield
    end

    after do
      Fiber[:__rage_logger_tags] = nil
      Fiber[:__rage_logger_context] = nil
    end

    it "captures log tags and context from the parent fiber on initialization" do
      Fiber[:__rage_logger_tags] = ["request-abc"]
      Fiber[:__rage_logger_context] = { user_id: 42 }

      app = described_class.new([].each)

      expect(app.instance_variable_get(:@log_tags)).to eq(["request-abc"])
      expect(app.instance_variable_get(:@log_context)).to eq({ user_id: 42 })
    end

    it "restores log context in the streaming fiber for enumerator streams" do
      Fiber[:__rage_logger_tags] = ["request-abc"]
      Fiber[:__rage_logger_context] = { user_id: 42 }

      app = described_class.new([1].each)

      # clear fiber-locals to simulate a new fiber with no inherited context
      Fiber[:__rage_logger_tags] = nil
      Fiber[:__rage_logger_context] = nil

      app.on_open(connection)

      expect(Fiber[:__rage_logger_tags]).to eq(["request-abc"])
      expect(Fiber[:__rage_logger_context]).to eq({ user_id: 42 })
    end

    it "restores log context in the streaming fiber for proc streams" do
      Fiber[:__rage_logger_tags] = ["request-def"]
      Fiber[:__rage_logger_context] = { tenant: "acme" }

      app = described_class.new(->(conn) { conn.close })

      Fiber[:__rage_logger_tags] = nil
      Fiber[:__rage_logger_context] = nil

      app.on_open(connection)

      expect(Fiber[:__rage_logger_tags]).to eq(["request-def"])
      expect(Fiber[:__rage_logger_context]).to eq({ tenant: "acme" })
    end

    it "handles nil log context gracefully" do
      Fiber[:__rage_logger_tags] = nil
      Fiber[:__rage_logger_context] = nil

      app = described_class.new([1].each)
      app.on_open(connection)

      expect(Fiber[:__rage_logger_tags]).to be_nil
      expect(Fiber[:__rage_logger_context]).to be_nil
    end
  end
end

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

      expect(Iodine).to receive(:task_inc!)
      expect(Iodine).to receive(:task_dec!)

      app = described_class.new(stream)
      app.on_open(connection)
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
end

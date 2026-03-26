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

    it "does not double-close if the proc already closed the connection" do
      well_behaved_proc = ->(conn) {
        conn.write("data: hello\n\n")
        conn.close
      }

      app = described_class.new(well_behaved_proc)
      app.send(:start_raw_stream, connection)

      expect(connection.open?).to be false
      expect(connection.messages).to eq(["data: hello\n\n"])
    end

    it "closes the connection on normal completion even if proc forgets to close" do
      forgetful_proc = ->(conn) {
        conn.write("data: forgot to close\n\n")
        # User forgot to call conn.close
      }

      app = described_class.new(forgetful_proc)
      app.send(:start_raw_stream, connection)

      expect(connection.open?).to be false
    end
  end
end

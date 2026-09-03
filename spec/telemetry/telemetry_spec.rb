# frozen_string_literal: true

RSpec.describe Rage::Telemetry do
  describe ".__registry" do
    let(:span1) { double(id: "test.span.1") }
    let(:span2) { double(id: "test.span.2") }
    let(:spans_module) { Module.new }

    before do
      spans_module::Span1 = span1
      spans_module::Span2 = span2

      stub_const("#{described_class}::Spans", spans_module)
    end

    around do |example|
      Rage::Telemetry.instance_variable_set(:@__registry, nil)
      example.run
      Rage::Telemetry.instance_variable_set(:@__registry, nil)
    end

    it "correctly builds span registry" do
      expect(described_class.__registry).to eq({ "test.span.1" => span1, "test.span.2" => span2 })
    end

    context ".available_spans" do
      it "returns available span IDs" do
        expect(described_class.available_spans).to match_array(["test.span.1", "test.span.2"])
      end
    end
  end

  describe ".tracer" do
    around do |example|
      Rage::Telemetry.instance_variable_set(:@tracer, nil)
      example.run
      Rage::Telemetry.instance_variable_set(:@tracer, nil)
    end

    it "correctly initializes Tracer" do
      allow(described_class).to receive(:__registry).and_return(:test_span_registry)

      expect(described_class::Tracer).to receive(:new).with(:test_span_registry)
      described_class.tracer
    end
  end

  describe ".__setup" do
    let(:handlers_map) { double }

    it "calls Tracer#setup" do
      allow(described_class).to receive(:tracer).and_return(double)
      expect(described_class.tracer).to receive(:setup).with(handlers_map)

      described_class.__setup(handlers_map)
    end
  end

  describe ".queued_connections" do
    before do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
    end

    after do
      Fiber.set_scheduler(nil)
    end

    it "reports the accept-queue depth of the server's listeners" do
      require "socket"

      s = TCPServer.new("127.0.0.1", 0)
      port = s.addr[1]
      s.close
      result = nil

      Iodine.workers = 1
      Iodine.on_state(:on_start) do
        Iodine.listen(port: port, handler: -> { [200, {}, ["ok"]] })
        socks = 5.times.map { TCPSocket.new("127.0.0.1", port) }
        Iodine.run { result = described_class.queued_connections }
        socks.each(&:close)
        Iodine.run { Iodine.stop }
      end
      Iodine.start

      expect(result).to eq(5)
    end

    it "is callable from within the reactor via .every" do
      require "socket"

      s = TCPServer.new("127.0.0.1", 0)
      port = s.addr[1]
      s.close
      result = nil

      Iodine.workers = 1
      Iodine.on_state(:on_start) do
        Iodine.listen(port: port, handler: -> { [200, {}, ["ok"]] })
        Rage::Telemetry.every(5) do
          Iodine.run { result = described_class.queued_connections }
          Iodine.stop
        end
        Iodine.run_after(200) { Iodine.stop }
      end
      Iodine.start

      expect(result).to be_a(Integer)
    end
  end

  describe ".every" do
    context "when the reactor is not running" do
      it "registers the timer, which Iodine defers until the server starts" do
        allow(Iodine).to receive(:running?).and_return(false)
        expect(Iodine).to receive(:run_every).with(100)

        described_class.every(100) {}
      end
    end

    context "when the reactor is running" do
      it "registers the timer immediately" do
        allow(Iodine).to receive(:running?).and_return(true)
        expect(Iodine).to receive(:run_every).with(100)

        described_class.every(100) {}
      end

      it "executes the block in a fiber via Iodine.run_every" do
        allow(Iodine).to receive(:running?).and_return(true)

        received_block = nil
        allow(Iodine).to receive(:run_every) { |_ms, &block| received_block = block }

        Fiber.set_scheduler(Rage::FiberScheduler.new)
        my_block = -> { :did_run }
        described_class.every(100, &my_block)

        fiber = received_block.call
        expect(fiber.__get_result).to eq(:did_run)
      ensure
        Fiber.set_scheduler(nil)
      end
    end
  end

  describe "SpanResult" do
    subject { described_class::SpanResult }

    it "is in success state by default" do
      result = subject.new

      expect(result).to be_success
      expect(result).not_to be_error
      expect(result.exception).to be_nil
    end

    context "with exception" do
      it "is in failed state" do
        exception = StandardError.new
        result = subject.new(exception:)

        expect(result).not_to be_success
        expect(result).to be_error
        expect(result.exception).to eq(exception)
      end
    end
  end
end

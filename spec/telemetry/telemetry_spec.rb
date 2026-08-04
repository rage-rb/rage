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

  describe ".every" do
    context "when the reactor is not running" do
      it "defers registration until the server starts" do
        allow(Iodine).to receive(:running?).and_return(false)
        expect(Iodine).to receive(:on_state).with(:on_start)

        described_class.every(100) {}
      end
    end

    context "when the reactor is running" do
      it "registers the timer immediately" do
        allow(Iodine).to receive(:running?).and_return(true)
        expect(Iodine).to receive(:run_every).with(100)

        described_class.every(100) {}
      end
    end

    context "lag calculation" do
      let(:timer_block) { @timer_block }

      before do
        allow(Iodine).to receive(:running?).and_return(true)
        allow(Iodine).to receive(:run_every) { |&block| @timer_block = block }
      end

      it "yields the delay past the expected interval" do
        allow(Process).to receive(:clock_gettime).and_return(1000, 1130, 1230)

        received = []
        described_class.every(100) { |lag| received << lag }

        2.times { timer_block.call }

        expect(received).to eq([30, 0])
      end

      it "clamps negative lag to zero" do
        allow(Process).to receive(:clock_gettime).and_return(1000, 1099)

        received = []
        described_class.every(100) { |lag| received << lag }

        timer_block.call

        expect(received).to eq([0])
      end
    end

    context "within the reactor" do
      before do
        Fiber.set_scheduler(Rage::FiberScheduler.new)
      end

      after do
        Fiber.set_scheduler(nil)
      end

      it "periodically executes the block" do
        counter = 0

        within_reactor do
          described_class.every(50) { counter += 1 }
          sleep 0.28

          -> { expect(counter).to be >= 3 }
        end
      end

      it "yields a non-negative scheduling lag" do
        lags = []

        within_reactor do
          described_class.every(50) { |lag| lags << lag }
          sleep 0.28

          -> {
            expect(lags).not_to be_empty
            expect(lags).to all(be >= 0)
          }
        end
      end

      it "executes blocks registered before the server start" do
        counter = 0
        described_class.every(50) { counter += 1 }

        within_reactor do
          sleep 0.28

          -> { expect(counter).to be >= 3 }
        end
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

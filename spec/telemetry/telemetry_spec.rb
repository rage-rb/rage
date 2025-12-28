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
      allow(Rage.config.telemetry).to receive(:handlers_map).and_return(:test_handlers_map)

      expect(described_class::Tracer).to receive(:new).with(:test_span_registry, :test_handlers_map)
      described_class.tracer
    end
  end

  describe ".__setup" do
    it "calls Tracer#setup" do
      allow(described_class).to receive(:tracer).and_return(double)
      expect(described_class.tracer).to receive(:setup)

      described_class.__setup
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

# frozen_string_literal: true

RSpec.describe Rage::Telemetry::Tracer do
  subject { described_class.new(spans_registry, handlers_map) }

  let(:handler_arguments) { {} }
  let(:spans_registry) do
    {
      "cable.action.process" => double(
        id: "cable.action.process",
        span_parameters: span_parameters,
        handler_arguments: handler_arguments
      )
    }
  end

  let(:handlers_map) { {} }

  before do
    allow(Rage).to receive(:logger).and_return(double)
  end

  context "with no handlers" do
    context "with no span parameters" do
      let(:span_parameters) { [] }

      it "correctly builds tracer" do
        expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
      end

      it "returns the result of the block" do
        result = subject.span_cable_action_process { :test_result }
        expect(result).to eq(:test_result)
      end
    end

    context "with span parameters" do
      let(:span_parameters) { %w[channel: data:] }

      it "correctly builds tracer" do
        expect { |block| subject.span_cable_action_process(channel: nil, data: nil, &block) }.to yield_control.once
      end

      it "returns the result of the block" do
        result = subject.span_cable_action_process(channel: nil, data: nil) { :test_result }
        expect(result).to eq(:test_result)
      end
    end
  end

  context "with handlers" do
    let(:handler) do
      Class.new do
        def self.test_instrumentation
          verifier.call
          yield
        end
      end
    end

    let(:verifier) { double }
    let(:span_parameters) { [] }
    let(:handlers_map) do
      { "cable.action.process" => [Rage::Telemetry::HandlerRef[handler, :test_instrumentation]] }
    end

    before do
      allow(handler).to receive(:verifier).and_return(verifier)
      subject.setup
    end

    it "correctly builds tracer" do
      expect(verifier).to receive(:call)
      expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
    end

    it "returns the result of the block" do
      allow(verifier).to receive(:call)
      result = subject.span_cable_action_process { :test_result }
      expect(result).to eq(:test_result)
    end

    context "with span parameters" do
      let(:span_parameters) { %w[channel:] }

      it "correctly builds tracer" do
        expect(verifier).to receive(:call)
        expect { |block| subject.span_cable_action_process(channel: nil, &block) }.to yield_control.once
      end

      it "returns the result of the block" do
        allow(verifier).to receive(:call)
        result = subject.span_cable_action_process(channel: nil) { :test_result }
        expect(result).to eq(:test_result)
      end
    end

    context "with ID handler argument" do
      let(:handler) do
        Class.new do
          def self.test_instrumentation(id:)
            verifier.call(id)
            yield
          end
        end
      end

      it "passes span ID as argument" do
        expect(verifier).to receive(:call).with("cable.action.process")
        subject.span_cable_action_process {}
      end
    end

    context "with custom handler arguments" do
      let(:handler_arguments) { { name: '"TestAction"', data: ":test_data" } }

      context "with one parameter" do
        let(:handler) do
          Class.new do
            def self.test_instrumentation(name:)
              verifier.call(name)
              yield
            end
          end
        end

        it "passes correct arguments" do
          expect(verifier).to receive(:call).with("TestAction")
          subject.span_cable_action_process {}
        end
      end

      context "with multiple parameters" do
        let(:handler) do
          Class.new do
            def self.test_instrumentation(id:, name:)
              verifier.call(id, name)
              yield
            end
          end
        end

        it "passes correct arguments" do
          expect(verifier).to receive(:call).with("cable.action.process", "TestAction")
          subject.span_cable_action_process {}
        end
      end

      context "with splat" do
        let(:handler) do
          Class.new do
            def self.test_instrumentation(**payload)
              verifier.call(payload)
              yield
            end
          end
        end

        it "passes correct arguments" do
          expect(verifier).to receive(:call).with({
            id: "cable.action.process",
            name: "TestAction",
            data: :test_data
          })
          subject.span_cable_action_process {}
        end
      end
    end

    context "with no yield" do
      let(:handler) do
        Class.new do
          def self.test_instrumentation
          end
        end
      end

      it "yields control" do
        expect(Rage.logger).to receive(:warn) do |msg|
          expect(msg).to match(/Telemetry handler didn't call `yield`/)
          expect(msg).to include("cable.action.process")
        end

        expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
      end

      it "returns the result of the block" do
        allow(Rage.logger).to receive(:warn)
        result = subject.span_cable_action_process { :test_result }
        expect(result).to eq(:test_result)
      end
    end

    context "with span result" do
      let(:handler) do
        Class.new do
          def self.test_instrumentation
            verifier.call(yield)
          end
        end
      end

      it "returns an instance of SpanResult as a result of yield" do
        expect(verifier).to receive(:call) do |result|
          expect(result).to be_a(Rage::Telemetry::SpanResult)
          expect(result).to be_frozen
          expect(result).not_to be_error
        end

        subject.span_cable_action_process {}
      end
    end

    context "with exception inside span" do
      let(:handler) do
        Class.new do
          def self.test_instrumentation
            result = yield
            verifier.call(result)
          end
        end
      end

      it "re-raises the exception" do
        allow(verifier).to receive(:call)

        expect {
          subject.span_cable_action_process { raise "test error" }
        }.to raise_error("test error")
      end

      it "returns exception as part of span result in the handler" do
        expect(verifier).to receive(:call) do |result|
          expect(result).to be_a(Rage::Telemetry::SpanResult)
          expect(result).to be_frozen
          expect(result).to be_error
          expect(result.exception.message).to eq("test error")
        end

        begin
          subject.span_cable_action_process { raise "test error" }
        rescue
        end
      end
    end

    context "with exception inside handler" do
      context "with exception after yield" do
        let(:handler) do
          Class.new do
            def self.test_instrumentation
              yield
              raise "test error"
            end
          end
        end

        it "yields control" do
          allow(Rage.logger).to receive(:error)
          expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
        end

        it "logs the error" do
          expect(Rage.logger).to receive(:error) do |msg|
            expect(msg).to match(/Telemetry handler failed with error/)
            expect(msg).to include("test error")
          end

          subject.span_cable_action_process {}
        end

        it "returns the result of the block" do
          allow(Rage.logger).to receive(:error)

          result = subject.span_cable_action_process { :test_result }
          expect(result).to eq(:test_result)
        end
      end

      context "with exception before yield" do
        let(:handler) do
          Class.new do
            def self.test_instrumentation
              raise "test error"
              yield
            end
          end
        end

        it "yields control" do
          allow(Rage.logger).to receive(:error)
          allow(Rage.logger).to receive(:warn)
          expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
        end

        it "logs the error" do
          expect(Rage.logger).to receive(:error) do |msg|
            expect(msg).to match(/Telemetry handler failed with error/)
            expect(msg).to include("test error")
          end

          expect(Rage.logger).to receive(:warn) do |msg|
            expect(msg).to match(/Telemetry handler didn't call `yield`/)
            expect(msg).to include("cable.action.process")
          end

          subject.span_cable_action_process {}
        end

        it "returns the result of the block" do
          allow(Rage.logger).to receive(:error)
          allow(Rage.logger).to receive(:warn)

          result = subject.span_cable_action_process { :test_result }
          expect(result).to eq(:test_result)
        end
      end
    end
  end

  context "with multiple handlers" do
    let(:handler_1) do
      Class.new do
        def self.test_instrumentation_1(id:)
          verifier.call_1(id)
          yield
        end

        def self.test_instrumentation_2(name:)
          verifier.call_2(name)
          yield
        end
      end
    end

    let(:handler_2) do
      Class.new do
        def self.test_instrumentation_3(id:, data:)
          verifier.call_3(id, data)
          yield
        end
      end
    end

    let(:verifier) { double }
    let(:span_parameters) { [] }
    let(:handler_arguments) { { name: '"TestAction"', data: ":test_data" } }
    let(:handlers_map) do
      {
        "cable.action.process" => [
          Rage::Telemetry::HandlerRef[handler_1, :test_instrumentation_1],
          Rage::Telemetry::HandlerRef[handler_1, :test_instrumentation_2],
          Rage::Telemetry::HandlerRef[handler_2, :test_instrumentation_3]
        ]
      }
    end

    before do
      allow(handler_1).to receive(:verifier).and_return(verifier)
      allow(handler_2).to receive(:verifier).and_return(verifier)
      subject.setup
    end

    it "calls handlers in the correct order" do
      expect(verifier).to receive(:call_1).with("cable.action.process").ordered
      expect(verifier).to receive(:call_2).with("TestAction").ordered
      expect(verifier).to receive(:call_3).with("cable.action.process", :test_data).ordered

      subject.span_cable_action_process {}
    end

    it "yields control" do
      allow(verifier).to receive(:call_1)
      allow(verifier).to receive(:call_2)
      allow(verifier).to receive(:call_3)

      expect { |block| subject.span_cable_action_process(&block) }.to yield_control.once
    end

    it "returns the result of the block" do
      allow(verifier).to receive(:call_1)
      allow(verifier).to receive(:call_2)
      allow(verifier).to receive(:call_3)

      result = subject.span_cable_action_process { :test_result }
      expect(result).to eq(:test_result)
    end
  end
end

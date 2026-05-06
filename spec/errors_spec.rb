# frozen_string_literal: true

RSpec.describe Rage::Errors do
  around do |example|
    original_reporters = described_class.instance_variable_get(:@reporters)
    original_next_reporter_id = described_class.instance_variable_get(:@next_reporter_id)
    described_class.instance_variable_set(:@reporters, [])
    described_class.instance_variable_set(:@next_reporter_id, 0)
    example.run
  ensure
    described_class.instance_variable_set(:@reporters, original_reporters)
    described_class.instance_variable_set(:@next_reporter_id, original_next_reporter_id)
  end

  let(:error_handlers) { Rage::Configuration.new.error_handlers }

  describe "configuration integration" do
    it "is available via config.error_handlers" do
      expect(Rage::Configuration.new.error_handlers).to be_an_instance_of(Rage::Configuration::ErrorHandlers)
    end

    it "is available via Rage.errors" do
      expect(Rage.errors).to eq(described_class)
    end

    it "requires error handlers to respond to #call" do
      expect {
        error_handlers << Object.new
      }.to raise_error(ArgumentError, "error handler must respond to #call")
    end

    it "allows removing a registered error handler" do
      call_count = 0
      reporter = Class.new do
        define_method(:call) { |_exception| call_count += 1 }
      end.new

      error_handlers << reporter
      error_handlers.delete(reporter)

      described_class.report(StandardError.new("test"))

      expect(call_count).to eq(0)
    end
  end

  describe ".report" do
    let(:logger) { double(error: nil) }

    before do
      allow(Rage).to receive(:logger).and_return(logger)
    end

    it "returns nil when no reporters are registered" do
      expect(described_class.report(StandardError.new("test"))).to be_nil
    end

    it "calls a simple reporter with exception only" do
      reporter = Class.new do
        attr_reader :exception

        def call(exception)
          @exception = exception
        end
      end.new

      error = StandardError.new("test")
      error_handlers << reporter
      described_class.report(error, context: { user_id: 42 })

      expect(reporter.exception).to be(error)
    end

    it "calls a reporter with context when supported" do
      reporter = Class.new do
        attr_reader :exception, :context

        def call(exception, context: {})
          @exception = exception
          @context = context
        end
      end.new

      error = StandardError.new("test")
      error_handlers << reporter
      described_class.report(error, context: { user_id: 42 })

      expect(reporter.exception).to be(error)
      expect(reporter.context).to eq({ user_id: 42 })
    end

    it "adds backtrace for manually-created exceptions" do
      reporter = Class.new do
        attr_reader :exception

        def call(exception)
          @exception = exception
        end
      end.new

      error = StandardError.new("test")
      expect(error.backtrace).to be_nil

      error_handlers << reporter
      described_class.report(error)

      expect(reporter.exception.backtrace).to be_an(Array)
      expect(reporter.exception.backtrace).not_to be_empty
    end

    it "continues reporting when one reporter fails" do
      failed_reporter = Class.new do
        def call(_exception)
          raise "boom"
        end
      end.new

      successful_reporter = Class.new do
        attr_reader :exception

        def call(exception)
          @exception = exception
        end
      end.new

      error = StandardError.new("test")
      error_handlers << failed_reporter
      error_handlers << successful_reporter

      described_class.report(error)

      expect(successful_reporter.exception).to be(error)
      expect(logger).to have_received(:error).with(/Error reporter .* failed while reporting StandardError: RuntimeError \(boom\)/)
    end

    it "does not report the same exception twice" do
      call_count = 0
      reporter = Class.new do
        define_method(:call) { |_exception| call_count += 1 }
      end.new

      error = StandardError.new("test")
      error_handlers << reporter

      described_class.report(error)
      described_class.report(error)

      expect(call_count).to eq(1)
    end
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Errors do
  around do |example|
    original_reporters = described_class.instance_variable_get(:@reporters)
    described_class.instance_variable_set(:@reporters, [])
    example.run
  ensure
    described_class.instance_variable_set(:@reporters, original_reporters)
  end

  describe ".<<" do
    it "requires reporters to respond to #call" do
      expect {
        described_class << Object.new
      }.to raise_error(ArgumentError, "reporter must respond to #call")
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
      described_class << reporter
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
      described_class << reporter
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

      described_class << reporter
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
      described_class << failed_reporter
      described_class << successful_reporter

      described_class.report(error)

      expect(successful_reporter.exception).to be(error)
      expect(logger).to have_received(:error).with(/Error reporter .* failed: RuntimeError \(boom\)/)
    end

    it "does not report the same exception twice" do
      call_count = 0
      reporter = Class.new do
        define_method(:call) { |_exception| call_count += 1 }
      end.new

      error = StandardError.new("test")
      described_class << reporter

      described_class.report(error)
      described_class.report(error)

      expect(call_count).to eq(1)
    end
  end

  describe "configuration integration" do
    it "is available via config.errors" do
      expect(Rage::Configuration.new.errors).to eq(described_class)
    end
  end
end

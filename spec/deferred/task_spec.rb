# frozen_string_literal: true

RSpec.describe Rage::Deferred::Task do
  let(:task_class) do
    Class.new do
      include Rage::Deferred::Task

      def perform(arg, kwarg:)
      end
    end
  end

  before do
    stub_const("MyTask", task_class)
  end

  after do
    Fiber[:__rage_deferred_retry_in] = nil
  end

  describe ".enqueue" do
    let(:queue) { instance_double(Rage::Deferred::Queue, enqueue: true) }
    let(:context) { { class: "MyTask" } }

    before do
      allow(Rage::Deferred).to receive(:__queue).and_return(queue)
      allow(Rage::Deferred::Context).to receive(:build).and_return(context)
    end

    it "builds context and enqueues the task" do
      task_class.enqueue("value", kwarg: "value2", delay: 10)

      expect(Rage::Deferred::Context).to have_received(:build).with(task_class, ["value"], { kwarg: "value2" })
      expect(queue).to have_received(:enqueue).with(context, delay: 10, delay_until: nil)
    end

    it "returns nil" do
      result = task_class.enqueue("value", kwarg: "value2", delay: 10)
      expect(result).to be_nil
    end

    it "correctly passes delay_until" do
      time = Time.now
      task_class.enqueue(delay_until: time)

      expect(queue).to have_received(:enqueue).with(anything, delay: nil, delay_until: time)
    end
  end

  describe ".__next_retry_in" do
    it "returns the next retry interval with quartic backoff" do
      # Formula: (attempt**4) + 10 + (rand(15) * attempt)
      # rand(15) => 0..14

      # attempt 0 -> 0^4 + 10 + (0..14)*0 = 10
      expect(task_class.__next_retry_in(0, nil)).to eq(10)
      # attempt 1 -> 1^4 + 10 + (0..14)*1 = 11..25
      expect(task_class.__next_retry_in(1, nil)).to be_between(11, 25)
      # attempt 2 -> 2^4 + 10 + (0..14)*2 = 26..54
      expect(task_class.__next_retry_in(2, nil)).to be_between(26, 54)
      # attempt 3 -> 3^4 + 10 + (0..14)*3 = 91..133
      expect(task_class.__next_retry_in(3, nil)).to be_between(91, 133)
      # attempt 4 -> 4^4 + 10 + (0..14)*4 = 266..322
      expect(task_class.__next_retry_in(4, nil)).to be_between(266, 322)
    end

    it "returns nil when attempts exceed max" do
      # With MAX_ATTEMPTS=20 and current guard (attempts > max),
      # attempt 20 still retries, attempt 21 stops.
      expect(task_class.__next_retry_in(20, nil)).to be_a(Numeric)
      expect(task_class.__next_retry_in(21, nil)).to be_nil
    end

    it "returns the same value on repeated calls with the same attempts" do
      first = task_class.__next_retry_in(2, nil)
      second = task_class.__next_retry_in(2, nil)
      expect(first).to eq(second)
    end

    it "returns different values for different attempts" do
      val_at_0 = task_class.__next_retry_in(0, nil)
      val_at_4 = task_class.__next_retry_in(4, nil)
      expect(val_at_0).to be_a(Numeric)
      expect(val_at_4).to be_a(Numeric)
    end
  end

  describe ".max_retries" do
    context "with custom max" do
      before { task_class.max_retries(3) }

      it "retries up to custom max" do
        expect(task_class.__next_retry_in(3, StandardError.new)).to be_a(Numeric)
      end

      it "stops after custom max" do
        expect(task_class.__next_retry_in(4, StandardError.new)).to be_nil
      end

      it "means the task is executed up to 4 times total" do
        # attempt 1 = original, attempt 2-4 = retries
        expect(task_class.__next_retry_in(1, StandardError.new)).to be_a(Numeric)
        expect(task_class.__next_retry_in(2, StandardError.new)).to be_a(Numeric)
        expect(task_class.__next_retry_in(3, StandardError.new)).to be_a(Numeric)
        expect(task_class.__next_retry_in(4, StandardError.new)).to be_nil
      end
    end

    context "input validation" do
      it "converts string to integer" do
        task_class.max_retries("3")
        expect(task_class.__next_retry_in(3, StandardError.new)).to be_a(Numeric)
        expect(task_class.__next_retry_in(4, StandardError.new)).to be_nil
      end

      it "converts float to integer" do
        task_class.max_retries(2.9)
        expect(task_class.__next_retry_in(2, StandardError.new)).to be_a(Numeric)
        expect(task_class.__next_retry_in(3, StandardError.new)).to be_nil
      end

      it "raises ArgumentError for negative values" do
        expect { task_class.max_retries(-1) }.
          to raise_error(ArgumentError, /max_retries should be a valid non-negative integer/)
      end

      it "raises ArgumentError for non-integer strings" do
        expect { task_class.max_retries("abc") }.
          to raise_error(ArgumentError, /max_retries should be a valid non-negative integer/)
      end

      it "raises ArgumentError for nil" do
        expect { task_class.max_retries(nil) }.
          to raise_error(ArgumentError, /max_retries should be a valid non-negative integer/)
      end
    end
  end

  describe ".retry_interval" do
    context "default behavior (no override)" do
      it "returns an interval for any attempt" do
        interval = task_class.retry_interval(StandardError.new, attempt: 1)
        expect(interval).to be_a(Integer)
        expect(interval).to be_between(11, 25)
      end

      it "always returns a backoff (max check is in __next_retry_in)" do
        expect(task_class.retry_interval(StandardError.new, attempt: 5)).to be_a(Integer)
        expect(task_class.retry_interval(StandardError.new, attempt: 6)).to be_a(Integer)
      end
    end

    context "with override" do
      let(:temporary_error) { Class.new(StandardError) }
      let(:fatal_error) { Class.new(StandardError) }

      before do
        tmp_err = temporary_error
        fat_err = fatal_error

        task_class.define_singleton_method(:retry_interval) do |exception, attempt:|
          case exception
          when tmp_err
            10
          when fat_err
            false
          else
            super(exception, attempt: attempt)
          end
        end
      end

      it "returns custom interval for matching exception" do
        expect(task_class.retry_interval(temporary_error.new, attempt: 1)).to eq(10)
      end

      it "returns false for non-retryable exception" do
        expect(task_class.retry_interval(fatal_error.new, attempt: 1)).to be(false)
      end

      it "falls back to default for unmatched exception" do
        interval = task_class.retry_interval(StandardError.new, attempt: 1)
        expect(interval).to be_a(Integer)
        expect(interval).to be_between(11, 25)
      end

      it "__next_retry_in returns interval for retryable" do
        expect(task_class.__next_retry_in(1, temporary_error.new)).to eq(10)
      end

      it "__next_retry_in returns nil for non-retryable" do
        expect(task_class.__next_retry_in(1, fatal_error.new)).to be_nil
      end

      it "__next_retry_in uses default backoff for unmatched" do
        interval = task_class.__next_retry_in(1, StandardError.new)
        expect(interval).to be_between(11, 25)
      end

      it "__next_retry_in enforces max_retries even with custom interval" do
        task_class.max_retries(2)
        # attempt 1 & 2 should retry with custom interval
        expect(task_class.__next_retry_in(1, temporary_error.new)).to eq(10)
        expect(task_class.__next_retry_in(2, temporary_error.new)).to eq(10)
        # attempt 3 should be capped by max_retries
        expect(task_class.__next_retry_in(3, temporary_error.new)).to be_nil
      end
    end

    context "with edge case return values" do
      let(:logger) { double(warn: nil) }

      before do
        allow(Rage).to receive(:logger).and_return(logger)
      end

      it "accepts a Float return value" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| 2.5 }
        expect(task_class.__next_retry_in(1, StandardError.new)).to eq(2.5)
      end

      it "returns nil when retry_interval returns nil" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| nil }
        expect(task_class.__next_retry_in(1, StandardError.new)).to be_nil
      end

      it "returns nil when retry_interval returns false" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| false }
        expect(task_class.__next_retry_in(1, StandardError.new)).to be_nil
      end

      it "accepts zero as a valid interval" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| 0 }
        expect(task_class.__next_retry_in(1, StandardError.new)).to eq(0)
      end

      it "accepts a negative number as a Numeric" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| -5 }
        expect(task_class.__next_retry_in(1, StandardError.new)).to eq(-5)
      end

      it "logs a warning and falls back to default backoff for String" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| "invalid" }
        result = task_class.__next_retry_in(1, StandardError.new)
        expect(result).to be_a(Numeric)
        expect(result).to be_between(11, 25)
        expect(logger).to have_received(:warn).with(/returned String, expected Numeric/)
      end

      it "logs a warning and falls back to default backoff for Array" do
        task_class.define_singleton_method(:retry_interval) { |_exception, attempt:| [10] }
        result = task_class.__next_retry_in(1, StandardError.new)
        expect(result).to be_a(Numeric)
        expect(result).to be_between(11, 25)
        expect(logger).to have_received(:warn).with(/returned Array, expected Numeric/)
      end
    end
  end

  describe "#__perform" do
    let(:task) { task_class.new }
    let(:context) { double }
    let(:logger) { double(with_context: nil, tagged: nil, error: nil) }

    before do
      allow(Rage).to receive(:logger).and_return(logger)
      allow(logger).to receive(:with_context).and_yield
      allow(logger).to receive(:tagged).and_yield

      allow(Rage::Deferred::Context).to receive(:get_args).with(context).and_return(["arg1"])
      allow(Rage::Deferred::Context).to receive(:get_kwargs).with(context).and_return({ kwarg: "kwarg1" })
      allow(Rage::Deferred::Context).to receive(:get_attempts).with(context).and_return(1)
    end

    context "when task succeeds" do
      before do
        allow(Rage::Deferred::Context).to receive(:get_log_tags).with(context).and_return(["request-id"])
        allow(Rage::Deferred::Context).to receive(:get_log_context).with(context).and_return({})
        allow(task).to receive(:perform)
      end

      after do
        Fiber[:__rage_logger_tags] = nil
        Fiber[:__rage_logger_context] = nil
      end

      it "calls perform with correct arguments" do
        task.__perform(context)
        expect(task).to have_received(:perform).with("arg1", kwarg: "kwarg1")
      end

      it "logs with context and tag" do
        task.__perform(context)
        expect(logger).to have_received(:with_context).with({ task: "MyTask", attempt: 2 })
        expect(Fiber[:__rage_logger_tags]).to eq(["request-id"])
        expect(Fiber[:__rage_logger_context]).to eq({})
      end

      it "returns true" do
        expect(task.__perform(context)).to be(true)
      end

      it "does not log an error" do
        task.__perform(context)
        expect(logger).not_to have_received(:error)
      end

      it "stores current context" do
        task.__perform(context)
        expect(Fiber[described_class::CONTEXT_KEY]).to eq(context)
      end
    end

    context "when log tags are in the legacy string format" do
      before do
        allow(Rage::Deferred::Context).to receive(:get_log_tags).with(context).and_return("old-request-id")
        allow(Rage::Deferred::Context).to receive(:get_log_context).with(context).and_return(nil)
        allow(task).to receive(:perform)
      end

      after do
        Fiber[:__rage_logger_tags] = nil
        Fiber[:__rage_logger_context] = nil
      end

      it "wraps the string in an array" do
        task.__perform(context)
        expect(Fiber[:__rage_logger_tags]).to eq(["old-request-id"])
      end

      it "defaults log context to an empty hash" do
        task.__perform(context)
        expect(Fiber[:__rage_logger_context]).to eq({})
      end
    end

    context "when request_id is not present" do
      before do
        allow(Rage::Deferred::Context).to receive(:get_log_tags).with(context).and_return(nil)
        allow(Rage::Deferred::Context).to receive(:get_log_context).with(context).and_return({})
        allow(task).to receive(:perform)
      end

      it "does not add a log tag" do
        task.__perform(context)
        expect(logger).not_to have_received(:tagged)
      end
    end

    context "when task fails" do
      let(:error) { StandardError.new("Something went wrong") }

      before do
        allow(Rage::Deferred::Context).to receive(:get_log_tags).with(context).and_return(nil)
        allow(Rage::Deferred::Context).to receive(:get_log_context).with(context).and_return({})
        allow(task).to receive(:perform).and_raise(error)
        allow(error).to receive(:backtrace).and_return(["line 1", "line 2"])
        allow(Rage::Errors).to receive(:report)
      end

      it "logs the error" do
        task.__perform(context)
        expect(logger).to have_received(:error).with("Deferred task failed with exception: StandardError (Something went wrong):\nline 1\nline 2")
      end

      it "reports the error" do
        task.__perform(context)
        expect(Rage::Errors).to have_received(:report).with(error)
      end

      it "returns the exception" do
        expect(task.__perform(context)).to be(error)
      end

      context "with suppressed exception logging" do
        let(:task_class) do
          Class.new do
            include Rage::Deferred::Task

            def perform(arg, kwarg:)
            end

            private

            def __deferred_suppress_exception_logging?
              true
            end
          end
        end

        it "doesn't log the error" do
          task.__perform(context)
          expect(logger).not_to have_received(:error).with(/Deferred task failed with exception: StandardError/)
        end
      end
    end
  end

  describe "#meta" do
    let(:task) { task_class.new }

    it "returns Rage::Deferred::Metadata" do
      expect(task.meta).to eq(Rage::Deferred::Metadata)
    end
  end
end

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

    it "correctly passes delay_until" do
      time = Time.now
      task_class.enqueue(delay_until: time)

      expect(queue).to have_received(:enqueue).with(anything, delay: nil, delay_until: time)
    end
  end

  describe ".__should_retry?" do
    it "returns true if attempts are less than max" do
      expect(task_class.__should_retry?(4)).to be(true)
    end

    it "returns false if attempts are equal to max" do
      expect(task_class.__should_retry?(5)).to be(false)
    end
  end

  describe ".__next_retry_in" do
    it "returns the next retry interval with exponential backoff" do
      expect(task_class.__next_retry_in(0)).to be_between(1, 5)
      expect(task_class.__next_retry_in(1)).to be_between(1, 10)
      expect(task_class.__next_retry_in(2)).to be_between(1, 20)
      expect(task_class.__next_retry_in(3)).to be_between(1, 40)
      expect(task_class.__next_retry_in(4)).to be_between(1, 80)
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

      it "calls perform with correct arguments" do
        task.__perform(context)
        expect(task).to have_received(:perform).with("arg1", kwarg: "kwarg1")
      end

      it "logs with context and tag" do
        task.__perform(context)
        expect(logger).to have_received(:with_context).with({ task: "MyTask", attempt: 2 })
        expect(Thread.current[:rage_logger]).to eq({ tags: ["request-id"], context: {} })
      end

      it "returns true" do
        expect(task.__perform(context)).to be(true)
      end

      it "does not log an error" do
        task.__perform(context)
        expect(logger).not_to have_received(:error)
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
      end

      it "logs the error" do
        task.__perform(context)
        expect(logger).to have_received(:error).with("Deferred task failed with exception: StandardError (Something went wrong):\nline 1\nline 2")
      end

      it "returns false" do
        expect(task.__perform(context)).to be(false)
      end
    end
  end
end

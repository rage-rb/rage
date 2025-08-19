# frozen_string_literal: true

RSpec.describe Rage::Deferred::Task do
  let(:task_class) do
    Class.new do
      include Rage::Deferred::Task
      def perform(arg, kwarg:); end
    end
  end

  before do
    stub_const("MyTask", task_class)
  end

  describe ".enqueue" do
    let(:queue) { instance_double(Rage::Deferred::Queue, enqueue: true) }
    let(:metadata) { { class: "MyTask" } }

    before do
      allow(Rage::Deferred).to receive(:__queue).and_return(queue)
      allow(Rage::Deferred::Metadata).to receive(:build).and_return(metadata)
    end

    it "builds metadata and enqueues the task" do
      task_class.enqueue("value", kwarg: "value2", delay: 10)

      expect(Rage::Deferred::Metadata).to have_received(:build).with(task_class, ["value"], { kwarg: "value2" })
      expect(queue).to have_received(:enqueue).with(metadata, delay: 10, delay_until: nil)
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
    let(:metadata) { double }
    let(:logger) { double(with_context: nil, tagged: nil, error: nil) }

    before do
      allow(Rage).to receive(:logger).and_return(logger)
      allow(logger).to receive(:with_context).and_yield
      allow(logger).to receive(:tagged).and_yield

      allow(Rage::Deferred::Metadata).to receive(:get_args).with(metadata).and_return(["arg1"])
      allow(Rage::Deferred::Metadata).to receive(:get_kwargs).with(metadata).and_return({ kwarg: "kwarg1" })
      allow(Rage::Deferred::Metadata).to receive(:get_attempts).with(metadata).and_return(1)
    end

    context "when task succeeds" do
      before do
        allow(Rage::Deferred::Metadata).to receive(:get_request_id).with(metadata).and_return("request-id")
        allow(task).to receive(:perform)
      end

      it "calls perform with correct arguments" do
        task.__perform(metadata)
        expect(task).to have_received(:perform).with("arg1", kwarg: "kwarg1")
      end

      it "logs with context and tag" do
        task.__perform(metadata)
        expect(logger).to have_received(:with_context).with({ task: "MyTask", attempt: 2 })
        expect(logger).to have_received(:tagged).with("request-id")
      end

      it "returns true" do
        expect(task.__perform(metadata)).to be(true)
      end

      it "does not log an error" do
        task.__perform(metadata)
        expect(logger).not_to have_received(:error)
      end
    end

    context "when request_id is not present" do
      before do
        allow(Rage::Deferred::Metadata).to receive(:get_request_id).with(metadata).and_return(nil)
        allow(task).to receive(:perform)
      end

      it "does not add a log tag" do
        task.__perform(metadata)
        expect(logger).not_to have_received(:tagged)
      end
    end

    context "when task fails" do
      let(:error) { StandardError.new("Something went wrong") }

      before do
        allow(Rage::Deferred::Metadata).to receive(:get_request_id).with(metadata).and_return(nil)
        allow(task).to receive(:perform).and_raise(error)
        allow(error).to receive(:backtrace).and_return(["line 1", "line 2"])
      end

      it "logs the error" do
        task.__perform(metadata)
        expect(logger).to have_received(:error).with("Deferred task failed with exception: StandardError (Something went wrong):\nline 1\nline 2")
      end

      it "returns false" do
        expect(task.__perform(metadata)).to be(false)
      end
    end
  end
end

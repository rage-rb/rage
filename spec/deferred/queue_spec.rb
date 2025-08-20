# frozen_string_literal: true

RSpec.describe Rage::Deferred::Queue do
  let(:backend) { double("backend", add: "task-id", remove: nil) }
  let(:task_class) { double("task_class", __should_retry?: false) }
  let(:task_instance) { double("task_instance", __perform: true) }
  let(:task_metadata) { "TestTask" }
  let(:backpressure_config) { nil }

  subject { described_class.new(backend) }

  before do
    allow(Rage.config.deferred).to receive(:backpressure).and_return(backpressure_config)
    allow(Rage::Deferred::Metadata).to receive(:get_task).with(task_metadata).and_return(task_class)
    allow(task_class).to receive(:new).and_return(task_instance)
    allow(Iodine).to receive(:run_after) { |&block| block.call }
    allow(Iodine).to receive(:stopping?).and_return(false)
    allow(Iodine).to receive(:task_inc!)
    allow(Iodine).to receive(:task_dec!)
    allow(Fiber).to receive(:schedule) { |&block| block.call }
  end

  describe "#enqueue" do
    it "adds the task to the backend" do
      expect(backend).to receive(:add).with(task_metadata, publish_at: nil, task_id: nil).and_return("new-id")
      subject.enqueue(task_metadata)
    end

    it "schedules the task for execution" do
      expect(subject).to receive(:schedule).with("task-id", task_metadata, publish_in: nil)
      subject.enqueue(task_metadata)
    end

    context "with a delay" do
      it "correctly calculates publish_at and publish_in" do
        delay = 60
        expect(backend).to receive(:add).with(task_metadata, publish_at: Time.now.to_i + delay, task_id: nil)
        expect(subject).to receive(:schedule).with("task-id", task_metadata, publish_in: delay)
        subject.enqueue(task_metadata, delay:)
      end
    end

    context "with a delay_until" do
      it "correctly calculates publish_at and publish_in" do
        delay_until = Time.now + 120
        expect(backend).to receive(:add).with(task_metadata, publish_at: delay_until.to_i, task_id: nil)
        expect(subject).to receive(:schedule).with("task-id", task_metadata, publish_in: 120)
        subject.enqueue(task_metadata, delay_until:)
      end
    end

    context "with backpressure enabled" do
      let(:backpressure_config) { OpenStruct.new(high_water_mark: 1, low_water_mark: 0, sleep_interval: 0.01, timeout_iterations: 2, timeout: 0.02) }

      before do
        Fiber[:rage_backpressure_applied] = false
      end

      it "does not apply backpressure if backlog is low" do
        expect(subject).not_to receive(:sleep)
        subject.enqueue(task_metadata)
      end

      it "applies backpressure if backlog is high" do
        subject.instance_variable_set(:@backlog_size, 2)
        allow(subject).to receive(:sleep) do
          subject.instance_variable_set(:@backlog_size, 0)
        end
        expect(subject).to receive(:sleep).once
        subject.enqueue(task_metadata)
      end

      it "raises a timeout error if backpressure timeout is reached" do
        subject.instance_variable_set(:@backlog_size, 2)
        allow(subject).to receive(:sleep)
        expect { subject.enqueue(task_metadata) }.to raise_error(Rage::Deferred::PushTimeout, "could not enqueue deferred task within 0.02 seconds")
      end
    end
  end

  describe "#schedule" do
    it "increments and decrements iodine task counter" do
      expect(Iodine).to receive(:task_inc!).ordered
      expect(Iodine).to receive(:task_dec!).ordered
      subject.schedule("task-id", task_metadata)
    end

    it "performs the task" do
      expect(task_instance).to receive(:__perform).with(task_metadata).and_return(true)
      subject.schedule("task-id", task_metadata)
    end

    context "when task completes successfully" do
      it "removes the task from the backend" do
        allow(task_instance).to receive(:__perform).and_return(true)
        expect(backend).to receive(:remove).with("task-id")
        subject.schedule("task-id", task_metadata)
      end
    end

    context "when task fails" do
      before do
        allow(task_instance).to receive(:__perform).and_return(false)
        allow(Rage::Deferred::Metadata).to receive(:inc_attempts).with(task_metadata).and_return(1)
      end

      context "and should be retried" do
        it "re-enqueues the task with a delay" do
          allow(task_class).to receive(:__should_retry?).with(1).and_return(true)
          allow(task_class).to receive(:__next_retry_in).with(1).and_return(30)
          expect(subject).to receive(:enqueue).with(task_metadata, delay: 30, task_id: "task-id")
          subject.schedule("task-id", task_metadata)
        end
      end

      context "and should not be retried" do
        it "removes the task from the backend" do
          allow(task_class).to receive(:__should_retry?).with(1).and_return(false)
          expect(backend).to receive(:remove).with("task-id")
          subject.schedule("task-id", task_metadata)
        end
      end
    end

    context "with a delay" do
      it "schedules with a delay in milliseconds" do
        expect(Iodine).to receive(:run_after).with(5000)
        subject.schedule("task-id", task_metadata, publish_in: 5)
      end

      it "does not affect backlog size" do
        expect { subject.schedule("task-id", task_metadata, publish_in: 5) }.not_to change { subject.backlog_size }
      end
    end

    context "without a delay" do
      it "schedules immediately" do
        expect(Iodine).to receive(:run_after).with(nil)
        subject.schedule("task-id", task_metadata)
      end

      it "increments and decrements backlog size" do
        expect { subject.schedule("task-id", task_metadata) }.to change { subject.backlog_size }.by(0)
        expect(subject.backlog_size).to eq(0)
      end
    end
  end
end

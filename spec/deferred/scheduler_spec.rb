# frozen_string_literal: true

RSpec.describe Rage::Deferred::Scheduler do
  let(:task) { double("Rage::Deferred::Task") }
  let(:tasks) { [{ interval: 60, task: task }] }
  let(:logger) { double("Logger", info: nil) }

  before do
    allow(Rage).to receive(:logger).and_return(logger)
    allow(Iodine).to receive(:run_every)
    allow(Rage::Internal).to receive(:pick_a_worker) { |&block| block.call }
    allow(task).to receive(:enqueue)
  end

  describe ".start" do
    it "does not start when no tasks are configured" do
      described_class.start([])
      expect(Iodine).not_to have_received(:run_every)
    end

    it "registers timers when leader is elected" do
      described_class.start(tasks)
      expect(Iodine).to have_received(:run_every).with(60_000)
    end

    it "does not register task timers when lock is not acquired" do
      allow(Rage::Internal).to receive(:pick_a_worker)
      described_class.start(tasks)
      expect(Iodine).not_to have_received(:run_every)
    end

    it "registers a timer for each task" do
      tasks = [
        { interval: 60, task: double(enqueue: true) },
        { interval: 120, task: double(enqueue: true) }
      ]
      described_class.start(tasks)
      expect(Iodine).to have_received(:run_every).with(60_000)
      expect(Iodine).to have_received(:run_every).with(120_000)
    end

    it "calls enqueue on the task when timer fires" do
      allow(Iodine).to receive(:run_every).with(60_000) { |&block| block.call }
      described_class.start(tasks)
      expect(task).to have_received(:enqueue)
    end

    it "passes the correct lock path to pick_a_worker" do
      described_class.start(tasks)
      expect(Rage::Internal).to have_received(:pick_a_worker).with(lock_path: Rage::Deferred::Scheduler::LOCK_PATH)
    end
  end
end

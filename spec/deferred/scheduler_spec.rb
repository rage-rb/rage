# frozen_string_literal: true

RSpec.describe Rage::Deferred::Scheduler do
  let(:task) { double("Rage::Deferred::Task") }
  let(:tasks) { [{ interval: 60, task: task }] }
  let(:logger) { double("Logger", debug?: false) }

  before do
    described_class.instance_variable_set(:@lock, nil)
    allow(Rage).to receive(:logger).and_return(logger)
    allow_any_instance_of(File).to receive(:flock).and_return(true)
    allow(task).to receive(:enqueue)
    allow(Iodine).to receive(:run_every)
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
      allow_any_instance_of(File).to receive(:flock).and_return(false)
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
  end

  describe ".elect_leader" do
    it "does not run block when lock is not acquired" do
      allow_any_instance_of(File).to receive(:flock).and_return(false)
      expect { |b| described_class.elect_leader(&b) }.not_to yield_control
    end

    it "runs block when lock is acquired" do
      expect { |b| described_class.elect_leader(&b) }.to yield_control
    end

    it "opens lock file only once across multiple calls" do
      allow_any_instance_of(File).to receive(:flock).and_return(false)
      allow(File).to receive(:open).once.and_call_original
      3.times { described_class.elect_leader {} }
      expect(File).to have_received(:open).once
    end
  end
end

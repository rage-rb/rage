# frozen_string_literal: true

RSpec.describe Rage::Deferred::Backends::Disk do
  let(:storage_path) { Pathname.new(Dir.mktmpdir) }
  let(:prefix) { "test_prefix" }
  let(:fsync_frequency) { 100 }
  let(:backend) { described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency) }

  after do
    FileUtils.remove_entry(storage_path)
  end

  describe "#initialize" do
    before do
      backend
    end

    it "creates the storage path if it doesn't exist" do
      expect(storage_path).to exist
    end

    it "creates a storage file if none exist" do
      expect(storage_path.glob("#{prefix}*").size).to eq(1)
    end
  end

  describe "#add" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:publish_at) { Time.now.to_i }
    let(:task_id) { "custom_task_id" }

    it "adds a task with a custom task ID" do
      backend.add(task, publish_at: publish_at, task_id: task_id)
      expect(backend.pending_tasks.map(&:first)).to include(task_id)
    end

    it "adds a task with an auto-generated task ID" do
      task_id = backend.add(task, publish_at: publish_at)
      expect(backend.pending_tasks.map(&:first)).to include(task_id)
    end
  end

  describe "#remove" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:task_id) { backend.add(task) }

    it "removes a task by its ID" do
      backend.remove(task_id)
      expect(backend.pending_tasks.map(&:first)).not_to include(task_id)
    end
  end

  describe "#pending_tasks" do
    let(:task) { "Rage::Deferred::Task" }
    let(:publish_at) { Time.now.to_i }

    before do
      backend.add(task, publish_at: publish_at)
    end

    it "returns a list of pending tasks" do
      pending_tasks = backend.pending_tasks
      expect(pending_tasks.size).to eq(1)
      expect(pending_tasks.first[1]).to eq(task)
    end

    it "handles corrupted entries gracefully" do
      backend.instance_variable_get(:@storage).write("corrupted_entry\n")
      expect { backend.pending_tasks }.not_to raise_error
    end
  end

  describe "#rotate_storage" do
    let(:task) { double("Rage::Deferred::Task") }

    before do
      allow(backend).to receive(:rotate_storage).and_call_original
      backend.add(task)
      backend.instance_variable_set(:@should_rotate, true)
    end

    it "rotates the storage when conditions are met" do
      backend.remove(task)
      expect(storage_path.glob("#{prefix}*").size).to eq(2)
    end
  end
end

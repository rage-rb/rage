# frozen_string_literal: true

RSpec.describe Rage::Deferred::Backends::Disk do
  let(:storage_path) { Pathname.new(Dir.mktmpdir) }
  let(:prefix) { "test_prefix" }
  let(:fsync_frequency) { 100 }
  let(:backend) { described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency) }
  let(:tasks_storage) { backend.instance_variable_get(:@tasks_storage) }

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
      expect(storage_path.glob("#{prefix}0-*").size).to eq(1)
    end
  end

  describe "#add_task" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:publish_at) { Time.now.to_i }
    let(:task_id) { "custom_task_id" }

    it "adds a task with a custom task ID" do
      backend.add_task(task, publish_at: publish_at, task_id: task_id)
      expect(backend.pending_tasks.map(&:first)).to include(task_id)
    end

    it "adds a task with an auto-generated task ID" do
      task_id = backend.add_task(task, publish_at: publish_at)
      expect(backend.pending_tasks.map(&:first)).to include(task_id)
    end
  end

  describe "#remove_task" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:task_id) { backend.add_task(task) }

    it "removes a task by its ID" do
      backend.remove_task(task_id)
      expect(backend.pending_tasks.map(&:first)).not_to include(task_id)
    end
  end

  describe "#pending_tasks" do
    let(:task) { "Rage::Deferred::Task" }
    let(:publish_at) { Time.now.to_i }

    before do
      backend.add_task(task, publish_at: publish_at)
    end

    it "returns a list of pending tasks" do
      pending_tasks = backend.pending_tasks
      expect(pending_tasks.size).to eq(1)
      expect(pending_tasks.first[1]).to eq(task)
    end

    it "handles corrupted entries gracefully" do
      tasks_storage.instance_variable_get(:@storage).write("corrupted_entry\n")
      expect { backend.pending_tasks }.not_to raise_error
    end
  end

  describe "#rotate_storage" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:task_id) { backend.add_task(task) }

    before do
      task_id
      tasks_storage.instance_variable_set(:@should_rotate, true)
    end

    it "rotates the storage when conditions are met" do
      backend.remove_task(task_id)
      expect(storage_path.glob("#{prefix}0-*").size).to eq(2)
    end

    it "ignores missing old storage files during async cleanup" do
      scheduled_cleanups = []
      allow(Iodine).to receive(:run_after) { |_, &block| scheduled_cleanups << block }

      old_storage = tasks_storage.instance_variable_get(:@storage)

      backend.remove_task(task_id)
      File.unlink(old_storage.path)

      expect(scheduled_cleanups.size).to eq(1)
      expect { scheduled_cleanups.first.call }.not_to raise_error
    end
  end

  describe "On Startup" do
    let(:task) { double("Rage::Deferred::Task") }
    let(:future_timestamps) { (1..20).to_a.map { Time.now.to_i + rand(1_000..10_000) } }

    it "With storage file containing timestamps in the future." do
      file = storage_path.join("#{prefix}0-#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")
      storage = file.open("a+b").tap { |f| f.flock(File::LOCK_EX) }

      future_timestamps.each_with_index do |future_timestamp, i|
        task_id_base = "#{future_timestamp}-#{Process.pid}-#{i}"
        serialized = Marshal.dump(["ClockTimeSkew", {}, { name: "ClockFutureTask#{i}" }, [], "req_id", {}]).dump
        entry = "add:#{task_id_base}:-1:#{serialized}"
        crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")
        storage.write("#{crc}:#{entry}\n")
      end

      storage.flock(File::LOCK_UN)

      backend = described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency)
      task_id = backend.add_task(task)

      expect(task_id.split("-").first.to_i).to be > future_timestamps.max
    end

    it "With multiple recovered storage files with varying timestamps." do
      future_timestamps.each_slice(5).each do |timestamps|
        recovered_file = storage_path.join("#{prefix}0-#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")
        recovered_storage = recovered_file.open("a+b").tap { |f| f.flock(File::LOCK_EX) }

        timestamps.each_with_index do |future_timestamp, i|
          task_id_base = "#{future_timestamp}-#{Process.pid}-#{i}"
          serialized = Marshal.dump(["ClockTimeSkew", {}, { name: "ClockFutureTask#{i}" }, [], "req_id", {}]).dump
          entry = "add:#{task_id_base}:0:#{serialized}"
          crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")
          recovered_storage.write("#{crc}:#{entry}\n")
        end
        recovered_storage.flock(File::LOCK_UN)
      end

      backend = described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency)
      task_id = backend.add_task(task)

      expect(task_id.split("-").first.to_i).to be > future_timestamps.max
    end

    it "With a recovered storage file already removed before async cleanup." do
      scheduled_cleanups = []
      recovered_storage = instance_double(File, path: storage_path.join("missing-recovered-storage"), close: nil)

      allow(Iodine).to receive(:run_after) { |_, &block| scheduled_cleanups << block }
      allow(recovered_storage).to receive(:rewind)
      allow(recovered_storage).to receive(:read).with(262_144).and_return(nil)

      tasks_storage.instance_variable_set(:@recovered_storages, [recovered_storage])
      backend.pending_tasks

      expect(scheduled_cleanups.size).to eq(1)
      expect { scheduled_cleanups.first.call }.not_to raise_error
    end

    it "With empty storage file." do
      before_init = Time.now.to_i
      task_id = backend.add_task(task)
      expect(task_id.split("-").first.to_i).to be >= before_init + 1
    end

    it "With only rem entries in a storage file." do
      past_timestamps = (1..20).to_a.map { Time.now.to_i - rand(1_000..10_000) }
      file = storage_path.join("#{prefix}0-#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")
      storage = file.open("a+b").tap { |f| f.flock(File::LOCK_EX) }

      past_timestamps.each_with_index do |timestamp, i|
        task_id = "#{timestamp}-#{Process.pid}-#{i}"
        entry = "rem:#{task_id}"
        crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")
        storage.write("#{crc}:#{entry}\n")
      end

      storage.flock(File::LOCK_UN)
      before_init = Time.now.to_i

      backend = described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency)
      task_id = backend.add_task(task)

      expect(task_id.split("-").first.to_i).to be >= before_init + 1
    end
  end

  describe "#remove_dead_tasks" do
    let(:exception) { RuntimeError.new("boom") }
    let(:context) { ["SendWelcomeEmail", [], {}, 0] }

    def add_dead_task(task_id)
      backend.add_dead_task(task_id, context, exception, task_class: "SendWelcomeEmail", attempts: 3)
    end

    it "removes the given dead tasks and keeps the others" do
      add_dead_task("1-1-1")
      add_dead_task("2-2-2")

      expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
      expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["2-2-2"])
      expect(storage_path.join("#{prefix}dead_tasks-0.tmp")).not_to exist
    end

    it "leaves the queue untouched when no ids match" do
      add_dead_task("1-1-1")

      expect(backend.remove_dead_tasks("nope")).to eq(0)
      expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["1-1-1"])
      expect(storage_path.join("#{prefix}dead_tasks-0.tmp")).not_to exist
    end

    it "raises instead of reporting zero when the store is already locked" do
      stub_const("#{described_class}::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
      backend.instance_variable_get(:@dead_tasks_storage).instance_variable_set(:@locked, true)

      expect { backend.remove_dead_tasks("1-1-1") }.to raise_error(Rage::Deferred::DeadTasksLockTimeout)
    end
  end
end

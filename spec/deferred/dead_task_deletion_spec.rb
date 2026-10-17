# frozen_string_literal: true

RSpec.describe Rage::Deferred::DeadTasks, "deletion" do
  let(:records) do
    [
      {
        id: "1700000001-1-1", task_class: "FirstTask", attempts: 2,
        enqueued_at: 1_700_000_001, failed_at: 1_700_000_011,
        exception_class: "RuntimeError", exception_message: "first failure",
        backtrace: [], context: Marshal.dump(["FirstTask", [], {}])
      },
      {
        id: "1700000002-1-2", task_class: "SecondTask", attempts: 3,
        enqueued_at: 1_700_000_002, failed_at: 1_700_000_012,
        exception_class: "RuntimeError", exception_message: "secret task payload",
        backtrace: [], context: Marshal.dump(["SecondTask", [], {}])
      }
    ]
  end
  let(:backend) do
    stored_records = records
    Class.new do
      attr_reader :removal_calls

      define_method(:initialize) do
        @removal_calls = []
      end

      define_method(:each_dead_task) do |&block|
        stored_records.dup.each(&block)
        self
      end

      define_method(:find_dead_task) do |id|
        stored_records.reverse_each.find { |record| record[:id] == id }
      end

      define_method(:remove_dead_tasks) do |ids|
        @removal_calls << ids
        selected_ids = Array(ids).to_h { |id| [id, true] }
        removed_ids = {}
        stored_records.delete_if do |record|
          selected_ids[record[:id]].tap { |selected| removed_ids[record[:id]] = true if selected }
        end
        removed_ids.length
      end
    end.new
  end
  subject(:dead_tasks) { described_class.new(backend) }

  describe "entry deletion" do
    it "uses the shared backend privately without an action handler" do
      entry = dead_tasks.find_by_id("1700000001-1-1")

      expect(Rage::Deferred::DeadTask.singleton_class.private_method_defined?(:new)).to eq(true)
      expect(entry).to respond_to(:delete)
      expect(entry).not_to respond_to(:actions_handler, :actions_handler=, :backend, :backend=)
      expect(entry.instance_variable_get(:@backend)).to equal(backend)
      expect(entry.instance_variables).not_to include(:@actions_handler, :@snapshot, :@collection)
    end

    it "returns true for the removal and false when the entry becomes stale" do
      entry = dead_tasks.find_by_id("1700000001-1-1")

      expect(entry.delete).to eq(true)
      expect(entry.delete).to eq(false)
      expect(dead_tasks.find_by_id("1700000002-1-2")).not_to be_nil
      expect(backend.removal_calls).to eq([
        "1700000001-1-1",
        "1700000001-1-1"
      ])
    end

    it "performs each entry deletion immediately" do
      results = dead_tasks.map(&:delete)

      expect(results).to eq([true, true])
      expect(backend.removal_calls).to eq([
        "1700000001-1-1",
        "1700000002-1-2"
      ])
      expect(records).to be_empty
    end
  end

  describe "collection deletion" do
    it "deletes one String ID" do
      expect(dead_tasks.delete("1700000001-1-1")).to eq(1)
      expect(records.map { |record| record[:id] }).to eq(["1700000002-1-2"])
      expect(backend.removal_calls).to eq([["1700000001-1-1"]])
    end

    it "deletes one flat Array with one normalized backend call" do
      expect(dead_tasks.delete(["1700000001-1-1", "1700000002-1-2"])).to eq(2)
      expect(records).to be_empty
      expect(backend.removal_calls).to eq([["1700000001-1-1", "1700000002-1-2"]])
    end

    it "deduplicates IDs and does not count missing IDs" do
      result = dead_tasks.delete([
        "1700000001-1-1",
        "missing",
        "1700000001-1-1"
      ])

      expect(result).to eq(1)
      expect(backend.removal_calls).to eq([["1700000001-1-1", "missing"]])
      expect(records.map { |record| record[:id] }).to eq(["1700000002-1-2"])
    end

    it "returns zero for an empty Array without backend access" do
      expect(backend).not_to receive(:remove_dead_tasks)

      expect(dead_tasks.delete([])).to eq(0)
      expect(records.length).to eq(2)
    end

    it "rejects invalid arity without backend access" do
      expect(backend).not_to receive(:remove_dead_tasks)

      expect { dead_tasks.delete }.to raise_error(ArgumentError)
      expect { dead_tasks.delete("1700000001-1-1", "1700000002-1-2") }.to raise_error(ArgumentError)
      expect(records.length).to eq(2)
    end

    it "validates all IDs before backend access" do
      invalid_arguments = [
        1,
        nil,
        :task_id,
        ["1700000001-1-1", 2],
        [["1700000001-1-1"]]
      ]
      expect(backend).not_to receive(:remove_dead_tasks)

      invalid_arguments.each do |argument|
        expect { dead_tasks.delete(argument) }.to raise_error(TypeError, "dead task ids must be Strings")
      end
      expect(records.length).to eq(2)
    end

    it "does not disclose an invalid value through its error or output" do
      invalid_id = Object.new
      allow(invalid_id).to receive(:inspect).and_return("secret task payload")
      error = nil

      expect {
        begin
          dead_tasks.delete(["1700000001-1-1", invalid_id])
        rescue TypeError => e
          error = e
        end
      }.to output("").to_stdout.and output("").to_stderr

      expect(error.message).not_to include("secret task payload")
      expect(records.length).to eq(2)
    end

    it "propagates backend errors unchanged" do
      error = Errno::EIO.new("delete failed")
      allow(backend).to receive(:remove_dead_tasks).and_raise(error)

      expect { dead_tasks.delete("1700000001-1-1") }.to raise_error { |raised| expect(raised).to equal(error) }
    end
  end
end

RSpec.describe Rage::Deferred::Backends::Nil, "dead-task deletion" do
  it "returns zero without persistence" do
    backend = described_class.new
    dead_tasks = Rage::Deferred::DeadTasks.new(backend)

    expect(dead_tasks.delete("missing")).to eq(0)
    expect(dead_tasks.delete(["missing", "missing"])).to eq(0)
    expect(dead_tasks.delete([])).to eq(0)
    expect(dead_tasks.to_a).to eq([])
  end
end

RSpec.describe Rage::Deferred::DeadTasks, "Disk deletion" do
  let(:storage_path) { Pathname.new(Dir.mktmpdir) }
  let(:prefix) { "dead_task_deletion" }
  let(:backend) do
    Rage::Deferred::Backends::Disk.new(path: storage_path, prefix: prefix, fsync_frequency: 100)
  end
  let(:dead_tasks) { described_class.new(backend) }
  let(:dead_tasks_path) { storage_path.join("#{prefix}dead_tasks-0") }
  let(:tmp_storage_path) { Pathname("#{dead_tasks_path}.tmp") }
  let(:dead_tasks_storage) { backend.instance_variable_get(:@dead_tasks_storage) }

  after do
    FileUtils.remove_entry(storage_path)
  end

  def add_dead_task(id, selected_backend = backend)
    selected_backend.add_dead_task(
      id,
      ["SensitiveTask", ["secret argument"], {}],
      RuntimeError.new("secret task payload"),
      task_class: "SensitiveTask",
      attempts: 3
    )
  end

  def stored_ids(selected_backend = backend)
    selected_backend.enum_for(:each_dead_task).map { |record| record[:id] }
  end

  def append_serialized_record(id, serialized_record)
    payload = "dead_task:#{id}:#{serialized_record}"
    crc = Zlib.crc32(payload).to_s(16).rjust(8, "0")
    dead_tasks_path.open("ab") { |storage| storage.write("#{crc}:#{payload}\n") }
  end

  it "uses one real compaction for a bulk deletion and keeps unrelated tasks" do
    %w[1-1-1 2-1-1 3-1-1].each { |id| add_dead_task(id) }
    allow(File).to receive(:rename).and_call_original

    expect(dead_tasks.delete(["1-1-1", "3-1-1", "3-1-1", "missing"])).to eq(2)
    expect(File).to have_received(:rename).with(tmp_storage_path, dead_tasks_path).once
    expect(stored_ids).to eq(["2-1-1"])
    expect(tmp_storage_path).not_to exist
  end

  it "deletes every starting entry once and excludes a concurrent append" do
    %w[1-1-1 2-1-1 3-1-1].each { |id| add_dead_task(id) }
    descriptor = nil
    yielded_ids = []
    deletion_results = []
    allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
      original.call do |storage, snapshot_end|
        descriptor ||= storage
        operation.call(storage, snapshot_end)
      end
    end

    dead_tasks.each do |entry|
      yielded_ids << entry.id
      add_dead_task("4-1-1") if yielded_ids.length == 1
      deletion_results << entry.delete
    end

    expect(yielded_ids).to eq(%w[1-1-1 2-1-1 3-1-1])
    expect(deletion_results).to eq([true, true, true])
    expect(descriptor).to be_closed
    expect(stored_ids).to eq(["4-1-1"])
  end

  it "keeps traversal stable during selective deletion" do
    %w[1-1-1 2-1-1 3-1-1].each { |id| add_dead_task(id) }
    yielded_ids = []

    dead_tasks.each do |entry|
      yielded_ids << entry.id
      entry.delete unless entry.id == "2-1-1"
    end

    expect(yielded_ids).to eq(%w[1-1-1 2-1-1 3-1-1])
    expect(stored_ids).to eq(["2-1-1"])
  end

  it "prints a selected decode diagnostic, keeps that record, and deletes later entries" do
    add_dead_task("1-1-1")
    stub_const("SelectedDeadTaskDecodeFailure", Class.new)
    serialized_record = Marshal.dump(SelectedDeadTaskDecodeFailure.new).dump
    hide_const("SelectedDeadTaskDecodeFailure")
    append_serialized_record("broken-id", serialized_record)
    add_dead_task("3-1-1")

    expect {
      dead_tasks.each(&:delete)
    }.to output(
      /ERROR: Can't deserialize the dead-lettered task with id broken-id: \((ArgumentError|NameError|TypeError)\)/
    ).to_stdout

    expect(dead_tasks.find_by_id("1-1-1")).to be_nil
    expect(dead_tasks.find_by_id("3-1-1")).to be_nil
    expect(backend.remove_dead_tasks("broken-id")).to eq(1)
  end

  it "serializes overlapping Fiber deletions across two backend instances" do
    other_backend = Rage::Deferred::Backends::Disk.new(path: storage_path, prefix: prefix, fsync_frequency: 100)
    other_dead_tasks = described_class.new(other_backend)
    other_storage = other_backend.instance_variable_get(:@dead_tasks_storage)
    %w[1-1-1 2-1-1 3-1-1 4-1-1].each { |id| add_dead_task(id) }
    first_result = nil
    first_delete = Fiber.new do
      first_result = dead_tasks.delete(["1-1-1", "2-1-1"])
      :complete
    end
    allow(dead_tasks_storage).to receive(:with_lock).and_wrap_original do |original, operation, &delete_operation|
      original.call(operation) do
        Fiber.yield(:locked)
        delete_operation.call
      end
    end

    expect(first_delete.resume).to eq(:locked)
    allow(other_storage).to receive(:sleep) do
      first_delete.resume if first_delete.alive?
    end
    second_result = other_dead_tasks.delete(["2-1-1", "3-1-1"])

    expect(first_result).to eq(2)
    expect(second_result).to eq(1)
    expect(first_result + second_result).to eq(3)
    expect(stored_ids(other_backend)).to eq(["4-1-1"])
  end

  it "propagates a lock timeout from entry deletion without reporting false" do
    add_dead_task("1-1-1")
    entry = dead_tasks.find_by_id("1-1-1")
    stub_const("Rage::Deferred::Backends::Disk::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
    dead_tasks_storage.instance_variable_set(:@locked, true)

    expect { entry.delete }.to raise_error(Rage::Deferred::DeadTasksLockTimeout, /delete tasks from/)
  ensure
    dead_tasks_storage.instance_variable_set(:@locked, false) if defined?(dead_tasks_storage)
  end

  it "propagates a temp-file failure without deleting or disclosing the payload" do
    add_dead_task("1-1-1")
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).
      with(tmp_storage_path, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY, 0o644).
      and_raise(Errno::EACCES, tmp_storage_path.to_s)
    error = nil

    expect {
      begin
        dead_tasks.delete("1-1-1")
      rescue Errno::EACCES => e
        error = e
      end
    }.to output("").to_stdout.and output("").to_stderr

    expect(error.message).not_to include("secret task payload")
    expect(error.message).not_to include("secret argument")
    expect(stored_ids).to eq(["1-1-1"])
  end

  it "propagates a rename failure without deleting or disclosing the payload" do
    add_dead_task("1-1-1")
    allow(File).to receive(:rename).with(tmp_storage_path, dead_tasks_path).and_raise(Errno::EIO)
    error = nil

    expect {
      begin
        dead_tasks.delete("1-1-1")
      rescue Errno::EIO => e
        error = e
      end
    }.to output("").to_stdout.and output("").to_stderr

    expect(error.message).not_to include("secret task payload")
    expect(error.message).not_to include("secret argument")
    expect(stored_ids).to eq(["1-1-1"])
  end

  it "raises when directory synchronization fails after replacement" do
    add_dead_task("1-1-1")
    allow(dead_tasks_storage).to receive(:sync_storage_directory).and_raise(Errno::EIO)

    expect { dead_tasks.delete("1-1-1") }.to raise_error(Errno::EIO)
    expect(dead_tasks.find_by_id("1-1-1")).to be_nil
  end
end

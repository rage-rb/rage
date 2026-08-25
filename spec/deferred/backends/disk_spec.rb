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
    it "creates the storage path if it doesn't exist" do
      nested_path = storage_path.join("a/b")
      expect(nested_path).not_to exist

      described_class.new(path: nested_path, prefix: prefix, fsync_frequency: fsync_frequency)

      expect(nested_path).to exist
    end

    it "creates a storage file if none exist" do
      backend
      expect(storage_path.glob("#{prefix}0-*").size).to eq(1)
    end

    it "fsyncs the storage directory after ensuring the dead-tasks file exists" do
      directory = instance_double(File)
      allow(File).to receive(:open).and_call_original
      expect(File).to receive(:open).with(storage_path, File::RDONLY).and_yield(directory)
      expect(directory).to receive(:fsync)

      backend
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

  describe "dead tasks" do
    let(:exception) { RuntimeError.new("boom") }
    let(:context) { ["SendWelcomeEmail", [], {}, 0] }
    let(:dead_tasks_path) { storage_path.join("#{prefix}dead_tasks-0") }
    let(:tmp_storage_path) { Pathname("#{dead_tasks_path}.tmp") }
    let(:lock_path) { storage_path.join("#{prefix}dead_tasks.lock") }
    let(:dead_tasks_storage) { backend.instance_variable_get(:@dead_tasks_storage) }

    def add_dead_task(task_id, exception = self.exception, context: self.context, attempts: 3)
      backend.add_dead_task(task_id, context, exception, task_class: "SendWelcomeEmail", attempts:)
    end

    def raised_exception(message = "boom")
      raise message
    rescue => e
      e
    end

    def stored_entries
      dead_tasks_path.binread.each_line.map do |line|
        crc, op, id, payload = line.chomp.split(":", 4)
        { line:, crc:, op:, id:, payload:, expected_crc: Zlib.crc32("#{op}:#{id}:#{payload}").to_s(16).rjust(8, "0") }
      end
    end

    def stored_records
      stored_entries.map { |entry| Marshal.load(entry[:payload].undump) }
    end

    describe "#initialize" do
      it "creates an empty live store and a lock file" do
        backend

        expect(dead_tasks_path).to exist
        expect(dead_tasks_path.size).to eq(0)
        expect(lock_path).to exist
      end

      it "does not truncate an existing live store when a second backend is opened" do
        add_dead_task("1-1-1")
        bytes = dead_tasks_path.binread

        described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency)

        expect(dead_tasks_path.binread).to eq(bytes)
      end
    end

    describe "#add_dead_task" do
      it "writes a checksummed newline-delimited entry" do
        exception = raised_exception
        started_at = Time.now.to_i

        returned = add_dead_task("1700000000-99-3", exception)
        finished_at = Time.now.to_i

        expect(returned).to eq("1700000000-99-3")
        expect(dead_tasks_path.binread).to end_with("\n")
        expect(dead_tasks_path.binread.count("\n")).to eq(1)

        entry = stored_entries.first
        expect(entry[:crc]).to eq(entry[:expected_crc])
        expect(entry[:op]).to eq("dead_task")
        expect(entry[:id]).to eq("1700000000-99-3")

        record = stored_records.first
        expect(record[:id]).to eq("1700000000-99-3")
        expect(record[:task_class]).to eq("SendWelcomeEmail")
        expect(record[:attempts]).to eq(3)
        expect(record[:enqueued_at]).to eq(1_700_000_000)
        expect(record[:failed_at]).to be_between(started_at, finished_at)
        expect(record[:exception_class]).to eq("RuntimeError")
        expect(record[:exception_message]).to eq("boom")
        expect(record[:backtrace]).to be_an(Array)
        expect(record[:backtrace]).not_to be_empty
        expect(record[:context]).to eq(Marshal.dump(context))
      end

      it "appends without rewriting existing entries" do
        add_dead_task("1-1-1")
        first = dead_tasks_path.binread
        add_dead_task("2-2-2")

        expect(dead_tasks_path.binread).to start_with(first)
        expect(stored_entries.map { |entry| [entry[:id], entry[:crc] == entry[:expected_crc]] }).to eq(
          [["1-1-1", true], ["2-2-2", true]]
        )
      end

      it "keeps a context containing a newline as a single record" do
        newline_context = ["SendWelcomeEmail", ["line\nbreak"], {}, nil, nil, nil, nil]

        add_dead_task("1-1-1", context: newline_context)

        expect(dead_tasks_path.binread.count("\n")).to eq(1)
        expect(stored_entries.first[:crc]).to eq(stored_entries.first[:expected_crc])
        expect(Marshal.load(stored_records.first[:context])).to eq(newline_context)
      end

      it "caps the stored backtrace" do
        exception = raised_exception
        exception.set_backtrace(Array.new(50) { |i| "frame#{i}" })

        add_dead_task("1-1-1", exception)

        expect(stored_records.first[:backtrace]).to eq(Array.new(20) { |i| "frame#{i}" })
      end

      it "fsyncs the live file after appending" do
        backend
        fsynced = []
        allow_any_instance_of(File).to receive(:fsync).and_wrap_original do |original|
          fsynced << original.receiver.path
          original.call
        end

        add_dead_task("1-1-1")

        expect(fsynced).to eq([dead_tasks_path.to_s])
      end

      it "repairs an incomplete final entry before appending" do
        add_dead_task("1-1-1")
        dead_tasks_path.open("ab") { |storage| storage.write("deadbeef:dead_task:partial") }

        add_dead_task("2-2-2")

        expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["2-2-2", "1-1-1"])
      end

      it "repairs a file containing only an incomplete entry before appending" do
        backend
        dead_tasks_path.open("wb") { |storage| storage.write("deadbeef:dead_task:partial") }

        add_dead_task("1-1-1")

        expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["1-1-1"])
      end

      it "repairs a torn tail longer than one scan chunk" do
        add_dead_task("1-1-1")
        first = dead_tasks_path.binread
        dead_tasks_path.open("ab") { |storage| storage.write("\x01" * 20_000) }

        add_dead_task("2-2-2")

        expect(stored_entries.map { |entry| entry[:id] }).to eq(["1-1-1", "2-2-2"])
        expect(dead_tasks_path.binread).to eq(first + stored_entries.last[:line])
      end

      it "repairs a torn tail that starts exactly one chunk from the end" do
        add_dead_task("1-1-1")
        first = dead_tasks_path.binread
        dead_tasks_path.open("ab") { |storage|
          storage.write("\x01" * described_class::DeadTasksStorage::TAIL_SCAN_CHUNK_SIZE)
        }

        add_dead_task("2-2-2")

        expect(stored_entries.map { |entry| entry[:id] }).to eq(["1-1-1", "2-2-2"])
        expect(dead_tasks_path.binread).to eq(first + stored_entries.last[:line])
      end

      it "truncates a file that is a single oversized incomplete write" do
        backend
        dead_tasks_path.open("wb") { |storage| storage.write("\x01" * 20_000) }

        add_dead_task("1-1-1")

        expect(stored_entries.map { |entry| entry[:id] }).to eq(["1-1-1"])
        expect(dead_tasks_path.binread).to eq(stored_entries.first[:line])
      end

      it "raises when another open file description holds the lock" do
        stub_const("#{described_class}::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
        backend
        holder = File.open(lock_path, File::WRONLY)
        holder.flock(File::LOCK_EX)

        begin
          expect {
            add_dead_task("1-1-1")
          }.to raise_error(Rage::Deferred::DeadTasksLockTimeout, /add a task to/)
          expect(dead_tasks_path.size).to eq(0)

          File.open(lock_path, File::WRONLY) do |third|
            expect(third.flock(File::LOCK_EX | File::LOCK_NB)).to eq(false)
          end

          holder.flock(File::LOCK_UN)
          add_dead_task("1-1-1")
          expect(stored_entries.map { |entry| entry[:id] }).to eq(["1-1-1"])
        ensure
          holder.flock(File::LOCK_UN)
          holder.close
        end
      end

      it "caps lock-retry backoff" do
        intervals = []
        allow(dead_tasks_storage).to receive(:sleep) { |interval| intervals << interval }
        dead_tasks_storage.instance_variable_set(:@locked, true)

        expect { add_dead_task("1-1-1") }.to raise_error(Rage::Deferred::DeadTasksLockTimeout)

        expect(intervals.size).to eq(19)
        expect(intervals).to eq((1..19).map { |attempt| [0.01 * attempt, 0.1].min })
        expect(intervals.max).to eq(described_class::DeadTasksStorage::LOCK_MAX_RETRY_INTERVAL)
      end
    end

    describe "#remove_dead_tasks" do
      it "removes the given dead tasks and keeps the others" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")

        expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
        expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["2-2-2"])
        expect(tmp_storage_path).not_to exist
      end

      it "removes several ids given as an array" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")
        add_dead_task("3-3-3")
        surviving = stored_entries[1]

        expect(backend.remove_dead_tasks(["1-1-1", "3-3-3"])).to eq(2)
        expect(dead_tasks_path.binread).to eq(surviving[:line])
        expect(tmp_storage_path).not_to exist
      end

      it "counts duplicate ids in the argument once" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")

        expect(backend.remove_dead_tasks(["1-1-1", "1-1-1"])).to eq(1)
        expect(stored_entries.map { |entry| entry[:id] }).to eq(["2-2-2"])
      end

      it "returns zero for empty input without creating a temp file" do
        add_dead_task("1-1-1")
        bytes = dead_tasks_path.binread

        expect(backend.remove_dead_tasks(nil)).to eq(0)
        expect(backend.remove_dead_tasks([])).to eq(0)
        expect(dead_tasks_path.binread).to eq(bytes)
        expect(tmp_storage_path).not_to exist
      end

      it "leaves an empty live file when every id is removed" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")

        expect(backend.remove_dead_tasks(["1-1-1", "2-2-2"])).to eq(2)
        expect(dead_tasks_path).to exist
        expect(dead_tasks_path.size).to eq(0)
        expect(tmp_storage_path).not_to exist
      end

      it "counts a twice-written id as a single deletion" do
        add_dead_task("1-1-1")
        add_dead_task("1-1-1")

        expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
        expect(dead_tasks_path.size).to eq(0)
      end

      it "drops corrupted and torn lines when a matching id is rewritten out" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")
        surviving = stored_entries[1]
        dead_tasks_path.open("ab") { |storage| storage.write("garbage\npartial") }

        expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
        expect(dead_tasks_path.binread).to eq(surviving[:line])
      end

      it "leaves corrupted residue in place when no ids match" do
        add_dead_task("1-1-1")
        dead_tasks_path.open("ab") { |storage| storage.write("garbage\npartial") }
        bytes = dead_tasks_path.binread

        expect(backend.remove_dead_tasks("absent")).to eq(0)
        expect(dead_tasks_path.binread).to eq(bytes)
        expect(tmp_storage_path).not_to exist
      end

      it "truncates a stale temp file instead of appending to it" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")
        surviving = stored_entries[1]
        tmp_storage_path.open("wb") { |storage| storage.write("stale-tmp-contents\n") }

        expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
        expect(dead_tasks_path.binread).to eq(surviving[:line])
        expect(dead_tasks_path.binread).not_to include("stale-tmp-contents")
        expect(tmp_storage_path).not_to exist
      end

      it "releases the lock when the rewrite raises" do
        add_dead_task("1-1-1")
        File.unlink(dead_tasks_path)

        expect { backend.remove_dead_tasks("1-1-1") }.to raise_error(Errno::ENOENT)

        File.open(lock_path, File::WRONLY) do |lock|
          expect(lock.flock(File::LOCK_EX | File::LOCK_NB)).to be_truthy
        end

        File.open(dead_tasks_path, File::WRONLY | File::CREAT | File::BINARY, 0o644) {}
        add_dead_task("2-2-2")
        expect(stored_entries.map { |entry| entry[:id] }).to eq(["2-2-2"])
      end

      it "fsyncs the storage directory after replacing the live file" do
        add_dead_task("1-1-1")

        expect(File).to receive(:rename).with(tmp_storage_path, dead_tasks_path).ordered.and_call_original
        expect(dead_tasks_storage).to receive(:sync_storage_directory).ordered.and_call_original

        backend.remove_dead_tasks("1-1-1")
      end

      it "fsyncs the temp file and directory only when a record is removed" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")
        fsynced = []
        allow_any_instance_of(File).to receive(:fsync).and_wrap_original do |original|
          fsynced << original.receiver.path
          original.call
        end

        backend.remove_dead_tasks("1-1-1")
        expect(fsynced).to eq([tmp_storage_path.to_s, storage_path.to_s])

        fsynced.clear
        backend.remove_dead_tasks("absent")
        expect(fsynced).to eq([])
      end

      it "leaves the queue untouched when no ids match" do
        add_dead_task("1-1-1")

        expect(backend.remove_dead_tasks("nope")).to eq(0)
        expect(backend.list_dead_tasks.map { |record| record[:id] }).to eq(["1-1-1"])
        expect(tmp_storage_path).not_to exist
      end

      it "raises instead of reporting zero when the store is already locked" do
        stub_const("#{described_class}::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
        dead_tasks_storage.instance_variable_set(:@locked, true)

        expect {
          backend.remove_dead_tasks("1-1-1")
        }.to raise_error(Rage::Deferred::DeadTasksLockTimeout, /delete tasks from/)
      end
    end

    it "shares one store across two backend instances" do
      other = described_class.new(path: storage_path, prefix: prefix, fsync_frequency: fsync_frequency)

      add_dead_task("1-1-1")
      other.add_dead_task("2-2-2", context, exception, task_class: "SendWelcomeEmail", attempts: 3)
      add_dead_task("3-3-3")

      expect(stored_entries.map { |entry| [entry[:id], entry[:crc] == entry[:expected_crc]] }).to eq(
        [["1-1-1", true], ["2-2-2", true], ["3-3-3", true]]
      )
      expect(storage_path.glob("#{prefix}dead_tasks-0")).to eq([dead_tasks_path])
      expect(storage_path.glob("#{prefix}dead_tasks.lock")).to eq([lock_path])
    end
  end
end

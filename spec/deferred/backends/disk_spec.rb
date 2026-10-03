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

        expect(backend.enum_for(:each_dead_task).map { |record| record[:id] }).to eq(["1-1-1", "2-2-2"])
      end

      it "repairs a file containing only an incomplete entry before appending" do
        backend
        dead_tasks_path.open("wb") { |storage| storage.write("deadbeef:dead_task:partial") }

        add_dead_task("1-1-1")

        expect(backend.enum_for(:each_dead_task).map { |record| record[:id] }).to eq(["1-1-1"])
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

    describe "#each_dead_task" do
      def each_dead_task
        backend.enum_for(:each_dead_task).to_a
      end

      def finish_external_traversal(iterator)
        records = []
        while true
          records << iterator.next
        end
      rescue StopIteration
        records
      end

      def append_physical_record(outer_id, record)
        entry = dead_tasks_storage.send(:build_entry, outer_id, record)
        dead_tasks_path.open("ab") { |storage| storage.write(entry) }
      end

      def append_serialized_record(outer_id, serialized_record)
        payload = "dead_task:#{outer_id}:#{serialized_record}"
        crc = Zlib.crc32(payload).to_s(16).rjust(8, "0")
        dead_tasks_path.open("ab") { |storage| storage.write("#{crc}:#{payload}\n") }
      end

      it "owns internal batching behind an argument-free backend traversal" do
        stub_const("#{described_class}::DeadTasksStorage::RECORD_BATCH_SIZE", 2)
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        add_dead_task("1700000003-1-3")

        expect(backend.method(:each_dead_task).parameters).to eq([[:block, :block]])
        expect { backend.each_dead_task(batch_size: 1) {} }.to raise_error(ArgumentError)
        expect(each_dead_task.map { |record| record[:id] }).to eq(
          ["1700000001-1-1", "1700000002-1-2", "1700000003-1-3"]
        )
      end

      it "removes eager reads from storage while retaining removal" do
        expect(dead_tasks_storage).not_to respond_to(:list, :find)
        expect(backend).to respond_to(:remove_dead_tasks)
      end

      it "yields the newest frame-valid duplicate" do
        add_dead_task("1700000001-1-1")
        older = stored_records.last
        append_physical_record("1700000001-1-1", older.merge(task_class: "NewTask", failed_at: older[:failed_at] + 1))

        records = each_dead_task

        expect(records.length).to eq(1)
        expect(records.first[:task_class]).to eq("NewTask")
      end

      it "orders a duplicate logical task at its winning record's position" do
        add_dead_task("1700000001-1-1")
        original = stored_records.last
        add_dead_task("1700000002-1-2")
        append_physical_record("1700000001-1-1", original.merge(task_class: "MovedTask"))

        records = each_dead_task

        expect(records.map { |record| record[:id] }).to eq(["1700000002-1-2", "1700000001-1-1"])
        expect(records.last[:task_class]).to eq("MovedTask")
      end

      it "falls back to an older duplicate only when newer frames are physically invalid" do
        add_dead_task("1700000001-1-1")
        dead_tasks_path.open("ab") { |storage| storage.write("deadbeef:dead_task:1700000001-1-1:garbage\n") }

        records = each_dead_task

        expect(records.length).to eq(1)
        expect(records.first[:id]).to eq("1700000001-1-1")
        expect(records.first[:task_class]).to eq("SendWelcomeEmail")
      end

      it "does not fall back when the newest frame-valid payload cannot be decoded" do
        add_dead_task("1700000001-1-1")
        append_serialized_record("1700000001-1-1", "not-a-dumped-string")

        expect { each_dead_task }.to raise_error(RuntimeError, /dumped string/)
      end

      it "silently skips malformed frames and an incomplete tail" do
        add_dead_task("1700000001-1-1")
        dead_tasks_path.open("ab") do |storage|
          storage.write("bad\n")
          storage.write("00000000:not_dead_task:id:payload\n")
          storage.write("deadbeef:dead_task:1700000002-1-2:secret-payload\n")
          storage.write("incomplete-secret-tail")
        end
        snapshot_bytes = dead_tasks_path.binread

        expect {
          expect(each_dead_task.map { |record| record[:id] }).to eq(["1700000001-1-1"])
        }.not_to output.to_stdout
        expect { each_dead_task }.not_to output.to_stderr
        expect(dead_tasks_path.binread).to eq(snapshot_bytes)
      end

      it "does not schema-check frame-valid payloads during selection" do
        add_dead_task("1700000001-1-1")
        valid = stored_records.last
        append_physical_record("1700000001-1-1", valid.merge(id: "inner-id", attempts: "three"))

        expect(each_dead_task).to contain_exactly(include(id: "1700000001-1-1", attempts: "three"))
      end

      it "does not deserialize opaque context bytes" do
        add_dead_task("1700000001-1-1")
        record = stored_records.last.merge(context: "not a Marshal payload")
        append_physical_record("1700000002-1-2", record.merge(id: "1700000002-1-2"))

        expect(each_dead_task.map { |entry| entry[:id] }).to eq(["1700000001-1-1", "1700000002-1-2"])
      end

      it "reads physical records larger than the reverse-reader chunk" do
        add_dead_task("1700000001-1-1")
        record = stored_records.last
        append_physical_record(
          "1700000002-1-2",
          record.merge(id: "1700000002-1-2", exception_message: "x" * 20_000)
        )

        expect(each_dead_task.map { |entry| entry[:id] }).to eq(["1700000001-1-1", "1700000002-1-2"])
      end

      it "returns the oldest 20 winning records" do
        25.times { |index| add_dead_task("170000#{index.to_s.rjust(4, "0")}-1-1") }

        ids = backend.enum_for(:each_dead_task).first(20).map { |record| record[:id] }

        expect(ids).to eq(20.times.map { |index| "170000#{index.to_s.rjust(4, "0")}-1-1" })
      end

      it "finishes frame-only winner selection before the first yield and decodes only the delivery batch" do
        stub_const("#{described_class}::DeadTasksStorage::RECORD_BATCH_SIZE", 2)
        5.times { |index| add_dead_task("170000000#{index}-1-1") }
        allow(Marshal).to receive(:load).and_call_original
        allow(dead_tasks_storage).to receive(:each_record_batch).and_wrap_original do |original, *args, &block|
          expect(Marshal).not_to have_received(:load)
          original.call(*args, &block)
        end

        first = backend.enum_for(:each_dead_task).first

        expect(first[:id]).to eq("1700000000-1-1")
        expect(Marshal).to have_received(:load).exactly(2).times
      end

      it "does not open or inspect a snapshot until first advancement" do
        add_dead_task("1700000001-1-1")
        allow(dead_tasks_storage).to receive(:with_snapshot).and_call_original
        allow(Marshal).to receive(:load).and_call_original

        iterator = backend.enum_for(:each_dead_task)

        expect(dead_tasks_storage).not_to have_received(:with_snapshot)
        expect(Marshal).not_to have_received(:load)

        iterator.next

        expect(dead_tasks_storage).to have_received(:with_snapshot).once
        expect(Marshal).to have_received(:load).once
      end

      it "excludes an incomplete tail and records appended after first advancement" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        dead_tasks_path.open("ab") { |storage| storage.write("deadbeef:dead_task:partial") }
        iterator = backend.enum_for(:each_dead_task)

        expect(iterator.next[:id]).to eq("1700000001-1-1")
        add_dead_task("1700000003-1-3")

        expect(finish_external_traversal(iterator).map { |record| record[:id] }).to eq(["1700000002-1-2"])
        expect(each_dead_task.map { |record| record[:id] }).to eq(
          ["1700000001-1-1", "1700000002-1-2", "1700000003-1-3"]
        )
      end

      it "keeps the captured inode stable across rename-based compaction" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        add_dead_task("1700000003-1-3")
        iterator = backend.enum_for(:each_dead_task)

        expect(iterator.next[:id]).to eq("1700000001-1-1")
        backend.remove_dead_tasks("1700000002-1-2")

        expect(finish_external_traversal(iterator).map { |record| record[:id] }).to eq(
          ["1700000002-1-2", "1700000003-1-3"]
        )
        expect(each_dead_task.map { |record| record[:id] }).to eq(["1700000001-1-1", "1700000003-1-3"])
      end

      it "releases the permanent lock before decoding and yielding" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        allow(Marshal).to receive(:load).and_wrap_original do |original, *args|
          expect(dead_tasks_storage.instance_variable_get(:@locked)).to eq(false)
          original.call(*args)
        end

        backend.each_dead_task do
          expect(dead_tasks_storage.instance_variable_get(:@locked)).to eq(false)
          File.open(lock_path, File::WRONLY) do |lock|
            expect(lock.flock(File::LOCK_EX | File::LOCK_NB)).to be_truthy
            lock.flock(File::LOCK_UN)
          end
        end
      end

      it "closes the snapshot after exhaustion, block exit, and terminal Enumerable exits" do
        add_dead_task("1700000001-1-1")
        descriptors = []
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptors << storage
            operation.call(storage, snapshot_end)
          end
        end
        collection = Rage::Deferred::DeadTasks.new(backend)

        backend.each_dead_task {}
        backend.each_dead_task { break }
        collection.find { true }
        collection.first
        collection.take(1)

        expect(descriptors.length).to eq(5)
        expect(descriptors).to all(be_closed)
      end

      it "keeps a partial external traversal open until it is exhausted" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        descriptor = nil
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptor = storage
            operation.call(storage, snapshot_end)
          end
        end
        iterator = backend.enum_for(:each_dead_task)

        iterator.next
        expect(descriptor).not_to be_closed

        finish_external_traversal(iterator)
        expect(descriptor).to be_closed
      end

      it "does not let cleanup replace an active user exception" do
        add_dead_task("1700000001-1-1")
        descriptor = nil
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptor = storage
            allow(descriptor).to receive(:close).and_wrap_original do |close|
              close.call
              raise Errno::EIO
            end
            operation.call(storage, snapshot_end)
          end
        end

        expect {
          backend.each_dead_task { raise "user failure" }
        }.to raise_error(RuntimeError, "user failure")
        expect(descriptor).to be_closed
      end

      it "propagates a descriptor cleanup error when it is the only failure" do
        add_dead_task("1700000001-1-1")
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            allow(storage).to receive(:close).and_wrap_original do |close|
              close.call
              raise Errno::EIO
            end
            operation.call(storage, snapshot_end)
          end
        end

        expect {
          backend.each_dead_task {}
        }.to raise_error(Errno::EIO)
      end

      it "propagates a descriptor cleanup error inside an unrelated rescue" do
        add_dead_task("1700000001-1-1")
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            allow(storage).to receive(:close).and_wrap_original do |close|
              close.call
              raise Errno::EIO
            end
            operation.call(storage, snapshot_end)
          end
        end

        begin
          raise "unrelated failure"
        rescue RuntimeError
          expect {
            backend.each_dead_task {}
          }.to raise_error(Errno::EIO)
        end
      end

      it "propagates a lock cleanup error inside an unrelated rescue" do
        lock_file = dead_tasks_storage.instance_variable_get(:@lock_file)
        allow(lock_file).to receive(:flock).and_wrap_original do |flock, operation|
          flock.call(operation).tap do
            raise Errno::EIO if operation == File::LOCK_UN
          end
        end

        begin
          raise "unrelated failure"
        rescue RuntimeError
          expect {
            backend.each_dead_task {}
          }.to raise_error(Errno::EIO)
        end
      end

      it "propagates lazy snapshot-acquisition failures and closes the opened descriptor" do
        descriptor = nil
        allow(dead_tasks_storage).to receive(:complete_record_end) do |storage|
          descriptor = storage
          raise Errno::EACCES
        end
        iterator = backend.enum_for(:each_dead_task)

        expect(descriptor).to be_nil
        expect { iterator.next }.to raise_error(Errno::EACCES)
        expect(descriptor).to be_closed
      end

      it "propagates reverse-read failures and closes the snapshot" do
        add_dead_task("1700000001-1-1")
        descriptor = nil
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptor = storage
            allow(descriptor).to receive(:seek).and_raise(Errno::EIO)
            operation.call(storage, snapshot_end)
          end
        end

        expect {
          backend.each_dead_task {}
        }.to raise_error(Errno::EIO)
        expect(descriptor).to be_closed
      end

      it "propagates snapshot lock timeouts on first advancement" do
        stub_const("#{described_class}::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
        dead_tasks_storage.instance_variable_set(:@locked, true)
        iterator = backend.enum_for(:each_dead_task)

        expect { iterator.next }.to raise_error(Rage::Deferred::DeadTasksLockTimeout, /read tasks from/)
      ensure
        dead_tasks_storage.instance_variable_set(:@locked, false)
      end

      it "keeps overlapping and Fiber-interleaved traversals independent" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        first = backend.enum_for(:each_dead_task)
        second = backend.enum_for(:each_dead_task)
        first_fiber = Fiber.new do
          ids = [first.next[:id]]
          Fiber.yield(ids.last)
          ids << first.next[:id]
          first.next
        rescue StopIteration
          ids
        end
        second_fiber = Fiber.new do
          ids = [second.next[:id]]
          Fiber.yield(ids.last)
          ids << second.next[:id]
          second.next
        rescue StopIteration
          ids
        end

        expect(first_fiber.resume).to eq("1700000001-1-1")
        expect(second_fiber.resume).to eq("1700000001-1-1")
        expect(first_fiber.resume).to eq(["1700000001-1-1", "1700000002-1-2"])
        expect(second_fiber.resume).to eq(["1700000001-1-1", "1700000002-1-2"])
      end

      it "establishes separate snapshots on each traversal's first advancement" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        first = backend.enum_for(:each_dead_task)
        second = backend.enum_for(:each_dead_task)

        expect(first.next[:id]).to eq("1700000001-1-1")
        add_dead_task("1700000003-1-3")
        expect(finish_external_traversal(second).map { |record| record[:id] }).to eq(
          ["1700000001-1-1", "1700000002-1-2", "1700000003-1-3"]
        )
        expect(finish_external_traversal(first).map { |record| record[:id] }).to eq(["1700000002-1-2"])
      end

      it "keeps nested traversals independent" do
        add_dead_task("1700000001-1-1")
        add_dead_task("1700000002-1-2")
        outer_ids = []
        nested_ids = nil

        backend.each_dead_task do |record|
          outer_ids << record[:id]
          nested_ids ||= each_dead_task.map { |nested| nested[:id] }
        end

        expect(outer_ids).to eq(["1700000001-1-1", "1700000002-1-2"])
        expect(nested_ids).to eq(outer_ids)
      end
    end

    describe "#find_dead_task" do
      let(:lookup_id) { "1700000001-1-1" }

      def append_lookup_record(outer_id, record)
        entry = dead_tasks_storage.send(:build_entry, outer_id, record)
        dead_tasks_path.open("ab") { |storage| storage.write(entry) }
      end

      def append_lookup_payload(outer_id, serialized_record)
        payload = "dead_task:#{outer_id}:#{serialized_record}"
        crc = Zlib.crc32(payload).to_s(16).rjust(8, "0")
        dead_tasks_path.open("ab") { |storage| storage.write("#{crc}:#{payload}\n") }
      end

      def store_lookup_record(mode)
        add_dead_task(lookup_id)
        original = stored_records.last

        case mode
        when :existing
          original
        when :duplicate
          original.merge(task_class: "NewestTask", failed_at: original[:failed_at] + 1).tap do |record|
            append_lookup_record(lookup_id, record)
          end
        when :schema_incompatible_duplicate
          original.merge(attempts: "invalid").tap do |record|
            append_lookup_record(lookup_id, record)
          end
        end
      end

      include_examples "a dead-task exact-lookup backend", empty: false

      it "falls back past physically corrupt matches and uses the outer id authoritatively" do
        add_dead_task(lookup_id)
        valid = stored_records.last
        dead_tasks_path.open("ab") { |storage| storage.write("deadbeef:dead_task:#{lookup_id}:secret\n") }

        expect { expect(backend.find_dead_task(lookup_id)).to eq(valid) }.not_to output.to_stdout
        expect { backend.find_dead_task(lookup_id) }.not_to output.to_stderr
      end

      it "returns a frame-valid schema-incompatible match and excludes an incomplete tail" do
        backend
        record = {
          id: lookup_id, task_class: "Task", attempts: "invalid",
          enqueued_at: 1, failed_at: 2, exception_class: "RuntimeError",
          exception_message: "secret", backtrace: [], context: Marshal.dump(["Task", [], {}])
        }
        append_lookup_record(lookup_id, record)
        dead_tasks_path.open("ab") { |storage| storage.write("incomplete-secret-tail") }
        bytes = dead_tasks_path.binread

        expect(backend.find_dead_task(lookup_id)).to eq(record)
        expect(dead_tasks_path.binread).to eq(bytes)
      end

      it "stops immediately after decoding the newest frame-valid match" do
        backend
        invalid_older = {
          id: lookup_id, task_class: "Task", attempts: "invalid",
          enqueued_at: 1, failed_at: 2, exception_class: "RuntimeError",
          exception_message: "older", backtrace: [], context: Marshal.dump(["Task", [], {}])
        }
        append_lookup_record(lookup_id, invalid_older)
        add_dead_task(lookup_id)
        allow(Marshal).to receive(:load).and_call_original

        expect(backend.find_dead_task(lookup_id)[:exception_message]).to eq("boom")
        expect(Marshal).to have_received(:load).once
      end

      it "propagates the selected payload decoding failure without falling back" do
        add_dead_task(lookup_id)
        append_lookup_payload(lookup_id, "not-a-dumped-string")

        expect { backend.find_dead_task(lookup_id) }.to raise_error(RuntimeError, /dumped string/)
      end

      it "uses the outer framed id when the decoded payload id differs" do
        add_dead_task(lookup_id)
        append_lookup_record(lookup_id, stored_records.last.merge(id: "different-id"))

        expect(backend.find_dead_task(lookup_id)[:id]).to eq(lookup_id)
      end

      it "finds records with incompatible opaque contexts without loading them" do
        add_dead_task(lookup_id)
        record = stored_records.last.merge(context: "not Marshal")
        append_lookup_record("1700000002-1-2", record.merge(id: "1700000002-1-2"))
        allow(Marshal).to receive(:load).and_call_original

        found = backend.find_dead_task("1700000002-1-2")

        expect(found[:id]).to eq("1700000002-1-2")
        expect(Marshal).to have_received(:load).once
      end

      it "uses an independent snapshot without disturbing a paused enumeration" do
        add_dead_task(lookup_id)
        add_dead_task("1700000002-1-2")
        iterator = backend.enum_for(:each_dead_task)

        expect(iterator.next[:id]).to eq(lookup_id)
        expect(backend.find_dead_task("1700000002-1-2")[:id]).to eq("1700000002-1-2")
        expect(iterator.next[:id]).to eq("1700000002-1-2")
        expect { iterator.next }.to raise_error(StopIteration)
      end

      it "propagates snapshot lock timeouts unchanged" do
        stub_const("#{described_class}::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
        dead_tasks_storage.instance_variable_set(:@locked, true)

        expect {
          backend.find_dead_task(lookup_id)
        }.to raise_error(Rage::Deferred::DeadTasksLockTimeout, /read tasks from/)
      ensure
        dead_tasks_storage.instance_variable_set(:@locked, false)
      end

      it "propagates open failures unchanged" do
        backend
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(dead_tasks_path, File::RDONLY | File::BINARY).and_raise(Errno::EACCES)

        expect { backend.find_dead_task(lookup_id) }.to raise_error(Errno::EACCES)
      end

      it "propagates reverse read failures and closes the snapshot" do
        add_dead_task(lookup_id)
        descriptor = nil
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptor = storage
            allow(descriptor).to receive(:seek).and_raise(Errno::EIO)
            operation.call(storage, snapshot_end)
          end
        end

        expect { backend.find_dead_task(lookup_id) }.to raise_error(Errno::EIO)
        expect(descriptor).to be_closed
      end

      it "does not let cleanup replace an active lookup failure" do
        add_dead_task(lookup_id)
        descriptor = nil
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            descriptor = storage
            allow(descriptor).to receive(:seek).and_raise(Errno::EACCES)
            allow(descriptor).to receive(:close).and_wrap_original do |close|
              close.call
              raise Errno::EIO
            end
            operation.call(storage, snapshot_end)
          end
        end

        expect { backend.find_dead_task(lookup_id) }.to raise_error(Errno::EACCES)
        expect(descriptor).to be_closed
      end

      it "propagates a descriptor cleanup error when it is the only failure" do
        add_dead_task(lookup_id)
        allow(dead_tasks_storage).to receive(:with_snapshot).and_wrap_original do |original, &operation|
          original.call do |storage, snapshot_end|
            allow(storage).to receive(:close).and_wrap_original do |close|
              close.call
              raise Errno::EIO
            end
            operation.call(storage, snapshot_end)
          end
        end

        expect { backend.find_dead_task(lookup_id) }.to raise_error(Errno::EIO)
      end

      it "propagates an operational failure after skipping a physically invalid match" do
        add_dead_task(lookup_id)
        reader_class = described_class::DeadTasksStorage.const_get(:ReverseLineReader, false)
        reader = instance_double(reader_class)
        allow(reader_class).to receive(:new).and_return(reader)
        allow(reader).to receive(:next_line).
          and_return([0, 42, "deadbeef:dead_task:#{lookup_id}:secret"]).
          and_raise(Errno::EIO)

        expect { backend.find_dead_task(lookup_id) }.to raise_error(Errno::EIO)
      end
    end

    describe "#remove_dead_tasks" do
      it "removes the given dead tasks and keeps the others" do
        add_dead_task("1-1-1")
        add_dead_task("2-2-2")

        expect(backend.remove_dead_tasks("1-1-1")).to eq(1)
        expect(backend.enum_for(:each_dead_task).map { |record| record[:id] }).to eq(["2-2-2"])
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
        expect(backend.enum_for(:each_dead_task).map { |record| record[:id] }).to eq(["1-1-1"])
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

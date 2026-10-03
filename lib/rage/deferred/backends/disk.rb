# frozen_string_literal: true

require "zlib"

##
# `Rage::Deferred::Backends` implements a storage layer to persist deferred tasks.
# A storage should implement the following instance methods:
#
# * `add_task` - called when a task has to be added to the storage;
# * `remove_task` - called when a task has to be removed from the storage;
# * `pending_tasks` - the method should iterate over the underlying storage and return a list of tasks to replay;
# * `add_dead_task` - called when a task has exhausted its retries or aborted them;
# * `each_dead_task` - traverse a stable dead-task snapshot oldest first;
# * `find_dead_task` - find a dead task by its exact id;
# * `remove_dead_tasks` - permanently delete dead tasks;
#
class Rage::Deferred::Backends::Disk
  def initialize(path:, prefix:, fsync_frequency:)
    @tasks_storage = TasksStorage.new(path:, prefix:, fsync_frequency:)
    @dead_tasks_storage = DeadTasksStorage.new(path:, prefix:)
  end

  # Add a record to the log representing a new task.
  # @param task [Rage::Deferred::Task]
  # @param publish_at [Integer, nil]
  # @param task_id [String, nil]
  # @return [String]
  def add_task(task, publish_at: nil, task_id: nil)
    @tasks_storage.add(task, publish_at:, task_id:)
  end

  # Add a record to the log representing a task removal.
  # @param task_id [String]
  def remove_task(task_id)
    @tasks_storage.remove(task_id)
  end

  # Return a list of pending tasks in the storage.
  # @return [Array<(String, Rage::Deferred::Task, Integer, Integer)>
  def pending_tasks
    @tasks_storage.pending_tasks
  end

  # Add a task to the dead-tasks store.
  # @param task_id [String] the id the task was persisted with
  # @param context [Array] the serializable execution context of the task
  # @param exception [Exception] the exception raised during the last attempt
  # @param task_class [Class, String] the class of the task
  # @param attempts [Integer] the number of attempts made to process the task
  # @return [String] the id of the dead-task record
  # @raise [Rage::Deferred::DeadTasksLockTimeout] if the dead-tasks store cannot be locked
  def add_dead_task(task_id, context, exception, task_class:, attempts:)
    @dead_tasks_storage.add(task_id, context, exception, task_class:, attempts:)
  end

  # Traverse logical dead-task records oldest-first from a stable snapshot.
  # @yieldparam record [Hash] a validated stored dead-task record
  # @return [Rage::Deferred::Backends::Disk::DeadTasksStorage]
  # @private
  def each_dead_task(&block)
    @dead_tasks_storage.each(&block)
  end

  # Find the newest fully valid dead-task record with the exact id.
  # @param id [String] persisted task id
  # @return [Hash, nil] a validated record, or nil
  # @private
  def find_dead_task(id)
    @dead_tasks_storage.find_by_id(id)
  end

  # Permanently delete dead-lettered tasks.
  # @param ids [String, Array<String>] the ids of the dead-task records
  # @return [Integer] the number of deleted records
  # @raise [Rage::Deferred::DeadTasksLockTimeout] if the dead-tasks store cannot be locked
  def remove_dead_tasks(ids)
    @dead_tasks_storage.remove(ids)
  end

  ##
  # The write-ahead log holding tasks that are yet to be processed. Every worker owns its own
  # storage file and never reads the files owned by the other workers, except during recovery.
  #
  # @private
  class TasksStorage
    STORAGE_VERSION = "0"
    STORAGE_SIZE_INCREASE_RATIO = 1.5

    DEFAULT_PUBLISH_AT = "0"
    DEFAULT_STORAGE_SIZE_LIMIT = 2_000_000

    def initialize(path:, prefix:, fsync_frequency:)
      @storage_path = path
      @storage_prefix = "#{prefix}#{STORAGE_VERSION}"
      @fsync_frequency = fsync_frequency

      @storage_path.mkpath

      # try to open and take ownership of all storage files in the storage directory
      storage_files = @storage_path.glob("#{@storage_prefix}-*").filter_map do |file_path|
        file = file_path.open("a+b")
        if file.flock(File::LOCK_EX | File::LOCK_NB)
          sleep 0.01 # reduce contention between workers
          file
        else
          file.close
        end
      end

      # if there are no storage files - create one;
      # otherwise the first one is used as the main storage; the rest will be merged into the main storage
      if storage_files.empty?
        @storage = create_storage
      else
        @storage = storage_files[0]
        @recovered_storages = storage_files[1..] if storage_files.length > 1
      end

      # include recovered storages from crashed/previous workers
      all_storages = [@storage, *@recovered_storages].compact

      # find the highest task timestamp across all storage files
      storage_file_max_timestamp = all_storages.map do |storage|
        max_timestamp = 0
        storage.tap(&:rewind).each_line(chomp: true) do |entry|
          next unless entry[9...12] == "add"
          timestamp = entry[13..].split("-").first.to_i
          max_timestamp = timestamp if timestamp > max_timestamp
        end
        max_timestamp
      end.max.to_i

      # apply Lamport IR2(b) From time, clocks and the ordering of
      # events in a distributed system to guard against clock skew
      task_id_seed = [Time.now.to_i, storage_file_max_timestamp].max + 1

      @task_id_base, @task_id_i = "#{task_id_seed}-#{Process.pid}", 0
      Iodine.run_every(1_000) do
        task_id_seed += 1
        @task_id_base, @task_id_i = "#{task_id_seed}-#{Process.pid}", 0
      end

      @storage_size_limit = DEFAULT_STORAGE_SIZE_LIMIT
      @storage_size = @storage.size
      @fsync_scheduled = false
      @should_rotate = false

      # we use different counters for different tasks:
      # delayed tasks are stored in the hash; for regular tasks we only maintain a counter;
      # this information is only used during storage rotation
      @immediate_tasks_in_queue = 0
      @delayed_tasks = {}

      # ensure data is written to disk
      @storage_has_changes = false
      Iodine.run_every(@fsync_frequency) do
        if @storage_has_changes
          @storage_has_changes = false
          @storage.fsync
        end
      end
    end

    # Add a record to the log representing a new task.
    # @param task [Rage::Deferred::Task]
    # @param publish_at [Integer, nil]
    # @param task_id [String, nil]
    # @return [String]
    def add(task, publish_at: nil, task_id: nil)
      serialized_task = Marshal.dump(task).dump

      persisted_task_id = task_id || generate_task_id

      entry = build_add_entry(persisted_task_id, serialized_task, publish_at)
      write_to_storage(entry)

      if publish_at
        @delayed_tasks[persisted_task_id] = [serialized_task, publish_at]
      else
        @immediate_tasks_in_queue += 1
      end

      persisted_task_id
    end

    # Add a record to the log representing a task removal.
    # @param task_id [String]
    def remove(task_id)
      write_to_storage(build_remove_entry(task_id))

      if @delayed_tasks.has_key?(task_id)
        @delayed_tasks.delete(task_id)
      else
        @immediate_tasks_in_queue -= 1
      end

      # rotate the storage once the size is over the limit and all non-delayed tasks are processed
      rotate_storage if @should_rotate && @immediate_tasks_in_queue == 0
    end

    # Return a list of pending tasks in the storage.
    # @return [Array<(String, Rage::Deferred::Task, Integer, Integer)>
    def pending_tasks
      if @recovered_storages
        # `@recovered_storages` will only be present if the server has previously crashed and left
        # some storage files behind, or if the new cluster is started with fewer workers than before;
        # TLDR: this code is expected to execute very rarely
        @recovered_storages.each { |storage| recover_tasks(storage.tap(&:rewind)) }
      end

      tasks = {}
      corrupted_tasks_count = 0

      # find pending tasks in the storage
      @storage.tap(&:rewind).each_line(chomp: true) do |entry|
        signature, op, payload = entry[0...8], entry[9...12], entry[9..]
        next if signature&.empty? || payload&.empty? || op&.empty?

        unless signature == Zlib.crc32(payload).to_s(16).rjust(8, "0")
          corrupted_tasks_count += 1
          next
        end

        if op == "add"
          task_id = entry[13...entry.index(":", 13).to_i]
          tasks[task_id] = entry
        elsif op == "rem"
          task_id = entry[13..]
          tasks.delete(task_id)
        end
      end

      if corrupted_tasks_count != 0
        puts "WARNING: Detected #{corrupted_tasks_count} corrupted deferred task(s)"
      end

      tasks.filter_map do |task_id, entry|
        _, _, _, serialized_publish_at, serialized_task = entry.split(":", 5)

        task = Marshal.load(serialized_task.undump)

        publish_at = (serialized_publish_at == DEFAULT_PUBLISH_AT ? nil : serialized_publish_at.to_i)

        if publish_at
          @delayed_tasks[task_id] = [serialized_task, publish_at]
        else
          @immediate_tasks_in_queue += 1
        end

        [task_id, task, publish_at]

      rescue ArgumentError, NameError => e
        puts "ERROR: Can't deserialize the task with id #{task_id}: (#{e.class}) #{e.message}"
        nil
      end
    end

    private

    def generate_task_id
      @task_id_i += 1
      "#{@task_id_base}-#{@task_id_i}"
    end

    def create_storage
      file = @storage_path.join("#{@storage_prefix}-#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")

      file.open("a+b").tap { |f| f.flock(File::LOCK_EX) }
    end

    def write_to_storage(content, adjust_size_limit: false)
      @storage.write(content)
      @storage_has_changes = true

      @storage_size += content.bytesize
      @should_rotate = true if @storage_size >= @storage_size_limit

      if adjust_size_limit
        # if the data copied from recovered storages or during the rotation takes up most of the storage, we might
        # end up in an infinite rotation loop; instead, we dynamically increase the storage size limit
        if @storage_size * STORAGE_SIZE_INCREASE_RATIO >= @storage_size_limit
          @storage_size_limit *= STORAGE_SIZE_INCREASE_RATIO
          @should_rotate = false
        end
      end
    end

    def rotate_storage
      old_storage = @storage
      @storage = nil # in case `create_storage` ends up blocking the fiber

      # create a new storage and update internal state;
      # after this point all new tasks will be written to the new storage
      @should_rotate = false
      @storage_size = 0
      @storage_size_limit = DEFAULT_STORAGE_SIZE_LIMIT
      @storage = create_storage

      # copy delayed tasks to the new storage in batches
      @delayed_tasks.keys.each_slice(100) do |task_ids|
        entries = task_ids.filter_map do |task_id|
          # don't copy the task if it has already been processed during the rotation
          next unless @delayed_tasks.has_key?(task_id)

          serialized_task, publish_at = @delayed_tasks[task_id]
          build_add_entry(task_id, serialized_task, publish_at)
        end

        write_to_storage(entries.join, adjust_size_limit: true)

        Fiber.pause
      end

      # delete the old storage ensuring the copied data has already been written to disk
      Iodine.run_after(@fsync_frequency) do
        cleanup_storage(old_storage)
      end
    end

    def build_add_entry(task_id, serialized_task, publish_at)
      entry = "add:#{task_id}:#{publish_at || DEFAULT_PUBLISH_AT}:#{serialized_task}"
      crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")

      "#{crc}:#{entry}\n"
    end

    def build_remove_entry(task_id)
      entry = "rem:#{task_id}"
      crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")

      "#{crc}:#{entry}\n"
    end

    def recover_tasks(storage)
      # copy records to the main storage
      while (content = storage.read(262_144))
        write_to_storage(content, adjust_size_limit: true)
      end

      Iodine.run_after(@fsync_frequency) do
        cleanup_storage(storage)
      end
    end

    def cleanup_storage(storage)
      path = storage.path
      storage.close
      File.unlink(path) if File.exist?(path)
    end
  end

  ##
  # Stores tasks that exhausted or aborted their retries so they can be inspected or replayed.
  #
  # All workers and processes share one append-only file. An exclusive, non-blocking file lock
  # serializes access; lock acquisition is retried briefly before an operation fails. Deletions
  # replace the file atomically, so a crash cannot leave a partially rewritten store.
  #
  # @private
  class DeadTasksStorage
    STORAGE_VERSION = "0"

    LOCK_MAX_ATTEMPTS = 20
    LOCK_RETRY_INTERVAL = 0.01
    LOCK_MAX_RETRY_INTERVAL = 0.1

    BACKTRACE_LIMIT = 20

    ENTRY_OP = "dead_task"
    ENTRY_CRC_HEX_WIDTH = 8
    TAIL_SCAN_CHUNK_SIZE = 8_192
    RECORD_BATCH_SIZE = 100

    REQUIRED_RECORD_TYPES = {
      id: String,
      task_class: String,
      attempts: Integer,
      enqueued_at: Integer,
      failed_at: Integer,
      exception_class: String,
      exception_message: String,
      backtrace: Array,
      context: String
    }.freeze

    # Returns complete lines one at a time while moving backward from a fixed
    # file boundary. It scans backward in fixed-size chunks to find the start of
    # each line, avoiding loading the entire preceding file contents into memory.
    #
    # @private
    class ReverseLineReader
      CHUNK_SIZE = 8_192
      private_constant :CHUNK_SIZE

      def initialize(storage, boundary, chunk_size: CHUNK_SIZE)
        @storage = storage
        @initial_scan_position = boundary
        @chunk_size = chunk_size
      end

      def next_line
        return if @initial_scan_position == 0

        line_end = @initial_scan_position - 1
        line_start = find_line_start(line_end)
        @initial_scan_position = line_start
        length = line_end - line_start

        @storage.seek(line_start, IO::SEEK_SET)
        [line_start, length, @storage.read(length)]
      end

      private

      def find_line_start(line_end)
        scan_position = line_end
        while scan_position > 0
          chunk_start = [scan_position - @chunk_size, 0].max
          @storage.seek(chunk_start, IO::SEEK_SET)
          chunk = @storage.read(scan_position - chunk_start)

          if (newline_index = chunk.rindex("\n"))
            return chunk_start + newline_index + 1
          end

          scan_position = chunk_start
        end

        0
      end
    end
    private_constant :RECORD_BATCH_SIZE, :REQUIRED_RECORD_TYPES, :ReverseLineReader

    # Open or create the shared dead-tasks store and its stable lock file.
    # @param path [Pathname] directory in which storage files are kept
    # @param prefix [String] prefix used for storage file names
    def initialize(path:, prefix:)
      path.mkpath

      @storage_path = path.join("#{prefix}dead_tasks-#{STORAGE_VERSION}")
      @tmp_storage_path = Pathname("#{@storage_path}.tmp")
      @lock_file = File.open(path.join("#{prefix}dead_tasks.lock"), File::WRONLY | File::CREAT, 0o644)
      @locked = false

      File.open(@storage_path, File::WRONLY | File::CREAT | File::BINARY, 0o644) {}
      sync_storage_directory
    end

    # Persist a failed task and its final error details.
    # @param task_id [String] id assigned when the task was enqueued
    # @param context [Object] serializable context needed to replay the task
    # @param exception [Exception] error raised by the final attempt
    # @param task_class [Class, String] task class or its name
    # @param attempts [Integer] number of processing attempts made
    # @return [String] the persisted task id
    # @raise [Rage::Deferred::DeadTasksLockTimeout] if the store cannot be locked
    def add(task_id, context, exception, task_class:, attempts:)
      record = {
        id: task_id,
        task_class: task_class.to_s,
        attempts: attempts.to_i,
        # the timestamp the task was originally enqueued at is a part of its id
        enqueued_at: task_id.to_s.split("-").first.to_i,
        failed_at: Time.now.to_i,
        exception_class: exception.class.name,
        exception_message: exception.message.to_s,
        backtrace: exception.backtrace&.first(BACKTRACE_LIMIT) || [],
        # the context is stored as an opaque blob so that reading the record never depends
        # on the task class being loadable in the process that reads it
        context: Marshal.dump(context)
      }

      entry = build_entry(task_id, record)

      with_lock("add a task to") do
        File.open(@storage_path, File::RDWR | File::APPEND | File::BINARY) do |storage|
          repair_torn_tail(storage)
          storage.write(entry)
          storage.fsync
        end

        task_id
      end
    end

    # Yield selected dead-task records oldest first.
    #
    # Under the lock, this opens the current file and records the end of its last
    # complete record. After releasing the lock, it scans that fixed view
    # backwards and selects the newest valid record for each task ID. It then
    # reads and yields those records oldest-first, keeping only one fixed-size
    # internal batch of decoded records in memory. All state belongs only to this call.
    #
    # @yieldparam record [Hash] a fully validated dead-task record
    # @return [self]
    # @raise [Rage::Deferred::DeadTasksLockTimeout] if the store cannot be locked
    # @raise [SystemCallError] when snapshot file operations fail
    def each
      with_snapshot do |storage, snapshot_end|
        records_index = build_records_index(storage, snapshot_end)
        each_record_batch(storage, records_index) { |record| yield record }

        self
      end
    end

    # Find the newest fully valid record with the exact authoritative framed id.
    # @param id [String] persisted task id
    # @return [Hash, nil] a fully validated record, or nil
    # @raise [Rage::Deferred::DeadTasksLockTimeout] if the store cannot be locked
    # @raise [SystemCallError] when snapshot file operations fail
    def find_by_id(id)
      with_snapshot do |storage, snapshot_end|
        reader = ReverseLineReader.new(storage, snapshot_end)

        loop do
          line = reader.next_line
          break unless line

          _offset, _length, entry = line
          framed_id, serialized_record = framed_record(entry)
          next unless framed_id == id

          record = decode_record(framed_id, serialized_record)
          return record if record
        end

        nil
      end
    end

    # Permanently delete the records with the given ids.
    # @param ids [String, Array<String>] one or more persisted task ids
    # @return [Integer] number of distinct records deleted
    # @raise [Rage::Deferred::DeadTasksLockTimeout] if the store cannot be locked
    def remove(ids)
      ids = Array(ids)
      return 0 if ids.empty?

      index = {}
      ids.each { |id| index[id] = true }

      with_lock("delete tasks from") do
        removed_ids = {}

        File.open(@tmp_storage_path, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY, 0o644) do |tmp|
          File.open(@storage_path, File::RDONLY | File::BINARY) do |storage|
            storage.each_line do |entry|
              id = entry_id(entry)

              if id.nil?
                next # drop corrupted records; they can neither be listed nor deleted otherwise
              elsif index[id]
                removed_ids[id] = true
              else
                tmp.write(entry)
              end
            end
          end

          tmp.fsync unless removed_ids.empty?
        end

        removed_count = removed_ids.length

        if removed_count > 0
          File.rename(@tmp_storage_path, @storage_path)
          sync_storage_directory
        else
          File.unlink(@tmp_storage_path)
        end

        removed_count
      end
    end

    private

    # Retain the newest valid serialized-payload location for every task ID.
    # @return [Hash{String => Array<(Integer, Integer)>}] payload locations in newest-first order
    def build_records_index(storage, snapshot_end)
      reader = ReverseLineReader.new(storage, snapshot_end)
      locations_by_id = {}

      loop do
        line = reader.next_line
        break unless line

        offset, length, entry = line
        framed_id, serialized_record = framed_record(entry)
        next unless framed_id
        next if locations_by_id.key?(framed_id)
        next unless decode_record(framed_id, serialized_record)

        serialized_record_offset = offset + length - serialized_record.bytesize
        locations_by_id[framed_id] = [serialized_record_offset, serialized_record.bytesize].freeze
      end

      locations_by_id
    end

    # Read selected payload locations oldest first and yield decoded records in batches.
    # @return [void]
    def each_record_batch(storage, records_index)
      batch = []

      records_index.reverse_each do |_framed_id, (offset, length)|
        storage.seek(offset, IO::SEEK_SET)
        batch << Marshal.load(storage.read(length).undump)
        next unless batch.length == RECORD_BATCH_SIZE

        batch.each { |batched_record| yield batched_record }
        batch.clear
      end

      batch.each { |record| yield record }
    end

    # Run a read against the current live file and its fixed complete-record boundary.
    # The descriptor is opened under the permanent lock, but the block runs after
    # the lock is released. Cleanup does not replace an exception already unwinding.
    # @yieldparam storage [File] snapshot descriptor
    # @yieldparam snapshot_end [Integer] fixed complete-record boundary
    # @yieldreturn [Object] result returned by the snapshot operation
    # @return [Object] the block result
    def with_snapshot
      storage = nil
      active_exception = nil

      begin
        snapshot_end = with_lock("read tasks from") do
          storage = File.open(@storage_path, File::RDONLY | File::BINARY)
          complete_record_end(storage)
        end

        yield storage, snapshot_end
      rescue Exception => e
        active_exception = e
        raise
      ensure
        begin
          storage.close if storage && !storage.closed?
        rescue
          raise unless active_exception
        end
      end
    end

    # Find the end of the last complete record without modifying the file,
    # excluding any unterminated bytes after the final newline.
    # @param storage [File] open live dead-task file
    # @return [Integer] fixed complete-record boundary
    def complete_record_end(storage)
      storage.seek(0, IO::SEEK_END)
      end_position = storage.pos
      return 0 if end_position == 0

      storage.seek(-1, IO::SEEK_END)
      return end_position if storage.read(1) == "\n"

      position = end_position
      while position > 0
        chunk_start = [position - TAIL_SCAN_CHUNK_SIZE, 0].max
        storage.seek(chunk_start, IO::SEEK_SET)
        chunk = storage.read(position - chunk_start)

        if (newline_index = chunk.rindex("\n"))
          return chunk_start + newline_index + 1
        end

        position = chunk_start
      end

      0
    end

    # Validate the physical frame and return its authoritative id and payload.
    # @param entry [String] one complete physical record without its newline
    # @return [Array<(String, String)>, nil]
    def framed_record(entry)
      return unless entry.bytesize > ENTRY_CRC_HEX_WIDTH + 1
      return unless entry.getbyte(ENTRY_CRC_HEX_WIDTH) == 58 # `:`

      signature = entry.byteslice(0, ENTRY_CRC_HEX_WIDTH)
      payload = entry.byteslice((ENTRY_CRC_HEX_WIDTH + 1)..)
      operation_prefix = "#{ENTRY_OP}:"
      return unless payload.start_with?(operation_prefix)
      return unless signature == Zlib.crc32(payload).to_s(16).rjust(ENTRY_CRC_HEX_WIDTH, "0")

      id_start = operation_prefix.bytesize
      separator_index = payload.index(":", id_start)
      return unless separator_index && separator_index > id_start

      [payload.byteslice(id_start...separator_index), payload.byteslice((separator_index + 1)..)]
    end

    # Decode and schema-check a framed record without decoding its opaque context.
    # @param framed_id [String] authoritative id from the physical frame
    # @param serialized_record [String] dumped top-level Hash
    # @return [Hash, nil]
    def decode_record(framed_id, serialized_record)
      record = Marshal.load(serialized_record.undump)
      return unless record.is_a?(Hash)
      return unless REQUIRED_RECORD_TYPES.all? { |key, type| record.key?(key) && record[key].is_a?(type) }
      return unless record[:backtrace].all? { |line| line.is_a?(String) }
      return unless record[:id] == framed_id

      record
    rescue ArgumentError, EOFError, NameError, RuntimeError, TypeError
      nil
    end

    # Persist changes to the live file's directory entry, including file creation and replacement.
    # @return [void]
    def sync_storage_directory
      File.open(@storage_path.dirname, File::RDONLY, &:fsync)
    end

    # Remove an incomplete final entry left by an interrupted append.
    # @param storage [File] store opened for reading and writing
    # @return [void]
    def repair_torn_tail(storage)
      truncate_at = complete_record_end(storage)
      storage.truncate(truncate_at) if truncate_at < storage.size
    end

    # Validate a stored entry and extract its task id.
    # @param entry [String] serialized entry, optionally ending with a newline
    # @return [String, nil] task id, or nil if the entry is malformed or corrupted
    def entry_id(entry)
      entry = entry.chomp

      signature, payload = entry[0...ENTRY_CRC_HEX_WIDTH], entry[(ENTRY_CRC_HEX_WIDTH + 1)..]
      return if signature.nil? || payload.nil? || !payload.start_with?("#{ENTRY_OP}:")
      return unless signature == Zlib.crc32(payload).to_s(16).rjust(ENTRY_CRC_HEX_WIDTH, "0")

      id_start = ENTRY_CRC_HEX_WIDTH + 1 + ENTRY_OP.length + 1
      separator_index = entry.index(":", id_start)
      entry[id_start...separator_index] if separator_index
    end

    # Serialize a task record as a checksummed, newline-delimited entry.
    # @param id [String] persisted task id
    # @param record [Hash] task data to serialize
    # @return [String] encoded storage entry
    def build_entry(id, record)
      entry = "#{ENTRY_OP}:#{id}:#{Marshal.dump(record).dump}"
      crc = Zlib.crc32(entry).to_s(16).rjust(ENTRY_CRC_HEX_WIDTH, "0")

      "#{crc}:#{entry}\n"
    end

    # Run an operation while holding the process-wide and file-system locks.
    # @param operation [String] action used to describe a lock timeout
    # @yieldreturn [Object] result returned by the protected operation
    # @return [Object] the block result
    # @raise [Rage::Deferred::DeadTasksLockTimeout] if the store cannot be locked
    def with_lock(operation)
      attempts = 0

      until !@locked && @lock_file.flock(File::LOCK_EX | File::LOCK_NB)
        attempts += 1

        if attempts == LOCK_MAX_ATTEMPTS
          raise Rage::Deferred::DeadTasksLockTimeout, "Could not lock the dead tasks store to #{operation} it"
        end

        # `sleep` is handled by the fiber scheduler and yields the fiber instead of the worker
        sleep [LOCK_RETRY_INTERVAL * attempts, LOCK_MAX_RETRY_INTERVAL].min
      end

      @locked = true
      active_exception = nil

      begin
        yield
      rescue Exception => e
        active_exception = e
        raise
      ensure
        begin
          @lock_file.flock(File::LOCK_UN)
        rescue
          raise unless active_exception
        ensure
          @locked = false
        end
      end
    end
  end
end

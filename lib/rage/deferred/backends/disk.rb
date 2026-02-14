# frozen_string_literal: true

require "zlib"

##
# `Rage::Deferred::Backends` implements a storage layer to persist deferred tasks.
# A storage should implement the following instance methods:
#
# * `add` - called when a task has to be added to the storage;
# * `remove` - called when a task has to be removed from the storage;
# * `pending_tasks` - the method should iterate over the underlying storage and return a list of tasks to replay;
#
class Rage::Deferred::Backends::Disk
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

    # create seed value for the task IDs
    task_id_seed = Time.now.to_i # TODO: ensure timestamps in the file are not higher
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
      @recovered_storages.each { |storage| recover_tasks(storage) }
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
      old_storage.close
      File.unlink(old_storage.path)
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
      storage.close
      File.unlink(storage.path)
    end
  end
end

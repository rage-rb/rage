# frozen_string_literal: true

RSpec.describe Rage::Deferred::DeadTask, "retry" do
  let(:storage_path) { Pathname.new(Dir.mktmpdir) }
  let(:prefix) { "dead_task_retry" }
  let(:backend) do
    Rage::Deferred::Backends::Disk.new(path: storage_path, prefix: prefix, fsync_frequency: 100)
  end
  let(:dead_tasks) { Rage::Deferred::DeadTasks.new(backend) }
  let(:queue) { Rage::Deferred::Queue.new(backend) }
  let(:enqueue_middleware) { [] }
  let(:perform_middleware) { [] }
  let(:middleware_chain) do
    Rage::Deferred::MiddlewareChain.new(enqueue_middleware:, perform_middleware:)
  end
  let(:tracer) { double("tracer") }
  let(:id) { "1700000000-1-1" }
  let(:entry) do
    store_dead_task(id)
    dead_tasks.find_by_id(id)
  end
  let(:dead_tasks_path) { storage_path.join("#{prefix}dead_tasks-0") }

  before do
    stub_const("RetryableDeadTask", Class.new do
      include Rage::Deferred::Task

      class << self
        attr_accessor :performed
      end

      self.performed = []

      def perform(*args, **kwargs)
        self.class.performed << [args, kwargs]
      end
    end)
    allow(Iodine).to receive(:running?).and_return(false)
    allow(Iodine).to receive(:run_every)
    allow(Rage.config.deferred).to receive(:backpressure).and_return(nil)
    allow(Rage::Deferred).to receive(:__queue).and_return(queue)
    allow(Rage::Deferred).to receive(:__middleware_chain) { middleware_chain }
    allow(Rage::Telemetry).to receive(:tracer).and_return(tracer)
    allow(tracer).to receive(:span_deferred_task_enqueue).and_yield
    allow(tracer).to receive(:span_deferred_task_process).and_yield
  end

  after do
    Rage::Deferred::MiddlewareChain.new(
      enqueue_middleware: Rage.config.deferred.enqueue_middleware.objects,
      perform_middleware: Rage.config.deferred.perform_middleware.objects
    )
    backend.instance_variable_get(:@tasks_storage).instance_variable_get(:@storage).close
    backend.instance_variable_get(:@dead_tasks_storage).instance_variable_get(:@lock_file).close
    FileUtils.remove_entry(storage_path)
  end

  def store_dead_task(task_id, args: ["original"], kwargs: { key: "value" }, task_class: "RetryableDeadTask")
    context = [task_class, args, kwargs, 7, ["old log tag"], { old: "log context" }, { old: "user context" }]
    backend.add_dead_task(task_id, context, RuntimeError.new("secret exception"), task_class:, attempts: 8)
  end

  def append_serialized_record(task_id, serialized)
    payload = "dead_task:#{task_id}:#{serialized}"
    crc = Zlib.crc32(payload).to_s(16).rjust(8, "0")
    dead_tasks_path.open("ab") { |file| file.write("#{crc}:#{payload}\n") }
  end

  def pending_tasks
    backend.pending_tasks
  end

  def retry_with_warning(selected_entry = entry)
    result = nil
    expect { result = selected_entry.retry }.to output(
      "Dead task #{selected_entry.id} was retried; server restart is required.\n"
    ).to_stderr
    result
  end

  def middleware(&block)
    Class.new { define_method(:call, &block) }
  end

  it "owns retry on entries only and uses the identical backend for each storage operation" do
    selected_entry = entry
    expect(dead_tasks).not_to respond_to(:retry)
    expect(selected_entry).not_to respond_to(:backend, :backend=, :actions_handler)
    expect(selected_entry.instance_variable_get(:@__backend)).to equal(backend)
    expect(selected_entry.instance_variables).not_to include(:@collection, :@snapshot, :@actions_handler)
    expect(backend).to receive(:find_dead_task).with(id).ordered.and_call_original
    expect(RetryableDeadTask).to receive(:enqueue).with("original", key: "value").ordered.and_call_original
    expect(backend).to receive(:flush_tasks).ordered.and_call_original
    expect(backend).to receive(:remove_dead_tasks).with(id).ordered.and_call_original

    expect(retry_with_warning(selected_entry)).to eq(true)
    expect(backend.instance_variable_get(:@dead_tasks_storage).find_by_id(id)).to be_nil
  end

  it "checks existence before resolving the class or decoding the context" do
    selected_entry = entry
    dead_tasks.delete(id)
    expect(Object).not_to receive(:const_get)
    expect(Marshal).not_to receive(:load)
    expect(RetryableDeadTask).not_to receive(:enqueue)
    expect(backend).not_to receive(:flush_tasks)
    expect(backend).not_to receive(:remove_dead_tasks)

    expect { expect(selected_entry.retry).to eq(false) }.to output("").to_stderr
    expect(pending_tasks).to be_empty
  end

  it "replays the entry snapshot after a same-ID replacement without constructing another entry" do
    selected_entry = entry
    cached_args, cached_kwargs = selected_entry.args, selected_entry.kwargs
    metadata = [selected_entry.task_class, selected_entry.attempts, selected_entry.failed_at]
    store_dead_task(id, args: ["replacement"], kwargs: {}, task_class: "RemovedReplacementTask")
    expect(described_class).not_to receive(:new)

    expect(retry_with_warning(selected_entry)).to eq(true)

    _, context, = pending_tasks.fetch(0)
    expect(Rage::Deferred::Context.get_task(context)).to equal(RetryableDeadTask)
    expect(Rage::Deferred::Context.get_args(context)).to eq(["original"])
    expect(Rage::Deferred::Context.get_kwargs(context)).to eq({ key: "value" })
    expect(selected_entry.args).to equal(cached_args)
    expect(selected_entry.kwargs).to equal(cached_kwargs)
    expect([selected_entry.task_class, selected_entry.attempts, selected_entry.failed_at]).to eq(metadata)
    expect(dead_tasks.find_by_id(id)).to be_nil
  end

  it "discards the existence-check result without constructing or validating an entry" do
    selected_entry = entry
    allow(backend).to receive(:find_dead_task).with(id).and_return(Object.new)

    expect(retry_with_warning(selected_entry)).to eq(true)
    expect(pending_tasks.length).to eq(1)
  end

  it "returns true if another operator removes the record after enqueue" do
    selected_entry = entry
    allow(backend).to receive(:flush_tasks).and_wrap_original do |original|
      original.call
      expect(backend.remove_dead_tasks(id)).to eq(1)
    end
    expect(backend).to receive(:remove_dead_tasks).with(id).twice.and_call_original

    expect(retry_with_warning(selected_entry)).to eq(true)
    expect(pending_tasks.length).to eq(1)
  end

  ["MissingRetryTask", "String", "RetryTaskValue", "RetryTaskNamespace", "Kernel.raise('must not execute')"].each do |class_name|
    it "rejects #{class_name.inspect} as a task class without changing storage" do
      stub_const("RetryTaskValue", 42)
      stub_const("RetryTaskNamespace", Module.new)
      store_dead_task(id, task_class: class_name)
      selected_entry = dead_tasks.find_by_id(id)
      expect(backend).not_to receive(:flush_tasks)
      expect(backend).not_to receive(:remove_dead_tasks)

      expect { selected_entry.retry }.to raise_error(Rage::Deferred::DeadTaskRetryError) { |error|
        expect(error.message).to include(id)
        expect(error.cause).to be_a(NameError) if class_name.start_with?("Missing", "Kernel.")
      }
      expect(dead_tasks.find_by_id(id)).not_to be_nil
      expect(pending_tasks).to be_empty
    end
  end

  it "resolves a namespaced task class" do
    stub_const("RetryNamespace", Module.new)
    stub_const("RetryNamespace::Task", Class.new { include Rage::Deferred::Task })
    store_dead_task(id, task_class: "RetryNamespace::Task")

    expect(retry_with_warning(dead_tasks.find_by_id(id))).to eq(true)
    expect(Rage::Deferred::Context.get_task(pending_tasks.first[1])).to equal(RetryNamespace::Task)
  end

  [[nil, nil], [["positional"], nil], [nil, { keyword: "value" }], [[1], { keyword: 2 }]].each do |args, kwargs|
    it "enqueues positional #{args.inspect} and keyword #{kwargs.inspect} arguments" do
      store_dead_task(id, args:, kwargs:)
      selected_entry = dead_tasks.find_by_id(id)
      expect(RetryableDeadTask).to receive(:enqueue).and_wrap_original do |original, *received_args, **received_kwargs|
        expect(received_args).to eq(args || [])
        expect(received_kwargs).to eq(kwargs || {})
        original.call(*received_args, **received_kwargs)
      end

      expect(retry_with_warning(selected_entry)).to eq(true)
      _, context, publish_at = pending_tasks.fetch(0)
      expect(Rage::Deferred::Context.get_args(context) || []).to eq(args || [])
      expect(Rage::Deferred::Context.get_kwargs(context) || {}).to eq(kwargs || {})
      expect(publish_at).to be_nil
    end
  end

  it "builds fresh ID, attempts, logger, and user context through public middleware and telemetry" do
    selected_entry = entry
    expect(tracer).to receive(:span_deferred_task_enqueue).with(task_class: RetryableDeadTask, context: instance_of(Array)).and_yield
    expect(middleware_chain).to receive(:with_enqueue_middleware).with(instance_of(Array), delay: nil, delay_until: nil).and_call_original

    expect(retry_with_warning(selected_entry)).to eq(true)

    new_id, context, publish_at = pending_tasks.fetch(0)
    expect(new_id).not_to eq(id)
    expect(Rage::Deferred::Context.get_attempts(context)).to be_nil
    expect(Rage::Deferred::Context.get_log_tags(context)).not_to eq(["old log tag"])
    expect(Rage::Deferred::Context.get_log_context(context)).not_to eq({ old: "log context" })
    expect(Rage::Deferred::Context.get_user_context(context)).to be_nil
    expect(publish_at).to be_nil
  end

  it "decodes mutable nested aliases and cycles independently of the frozen inspection cache" do
    shared = ["original"]
    shared << shared
    store_dead_task(id, args: [shared, shared], kwargs: { shared: })
    selected_entry = dead_tasks.find_by_id(id)
    cached_args, cached_kwargs = selected_entry.args, selected_entry.kwargs
    mutation = middleware do |args:, kwargs:, &block|
      raise "lost shared reference" unless args[0].equal?(args[1]) && args[0].equal?(kwargs[:shared])
      raise "lost cycle" unless args[0].equal?(args[0][1])

      args[0][0].replace("changed")
      kwargs[:shared] << "added"
      block.call
    end
    enqueue_middleware << [mutation, [], nil]

    expect(retry_with_warning(selected_entry)).to eq(true)

    context = pending_tasks.first[1]
    replay_args = Rage::Deferred::Context.get_args(context)
    replay_kwargs = Rage::Deferred::Context.get_kwargs(context)
    expect(replay_args[0]).to equal(replay_args[1])
    expect(replay_args[0]).to equal(replay_kwargs[:shared])
    expect(replay_args[0][1]).to equal(replay_args[0])
    expect(replay_args[0].values_at(0, 2)).to eq(["changed", "added"])
    expect(selected_entry.args).to equal(cached_args)
    expect(selected_entry.kwargs).to equal(cached_kwargs)
    expect(cached_args[0][0]).to eq("original")
    expect(cached_args[0].length).to eq(2)
    expect(cached_args[0]).to be_frozen
    expect(cached_args[0][0]).to be_frozen
  end

  it "normalizes nil arguments to fresh mutable values for each retry" do
    store_dead_task(id, args: nil, kwargs: nil)
    selected_entry = dead_tasks.find_by_id(id)
    seen = []
    allow(RetryableDeadTask).to receive(:enqueue) do |*args, **kwargs|
      seen << [args, kwargs]
      args << "changed"
      kwargs[:changed] = true
    end
    allow(backend).to receive(:remove_dead_tasks).and_return(0)

    2.times { expect(retry_with_warning(selected_entry)).to eq(true) }

    expect(seen[0][0]).not_to equal(seen[1][0])
    expect(seen[0][1]).not_to equal(seen[1][1])
    expect(selected_entry.args).to eq([])
    expect(selected_entry.kwargs).to eq({})
  end

  it "wraps an ordinary Marshal decoding failure with the ID and original cause" do
    selected_entry = entry
    record = backend.find_dead_task(id).merge(context: "not Marshal")
    append_serialized_record(id, Marshal.dump(record).dump)
    selected_entry = dead_tasks.find_by_id(id)
    expect(RetryableDeadTask).not_to receive(:enqueue)

    expect { selected_entry.retry }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
      expect(error.message).to include(id)
      expect(error.cause).to be_a(TypeError)
    }
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks).to be_empty
  end

  it "wraps custom Marshal decoding failures and leaves the record stored" do
    failure = RuntimeError.new("custom load failed")
    argument_class = Class.new do
      def marshal_dump
        "payload"
      end
    end
    argument_class.define_method(:marshal_load) { |_| raise failure }
    stub_const("RetryArgument", argument_class)
    store_dead_task(id, args: [RetryArgument.new])
    selected_entry = dead_tasks.find_by_id(id)

    expect { selected_entry.retry }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
      expect(error.message).to include(id)
      expect(error.cause).to equal(failure)
    }
    expect(dead_tasks.find_by_id(id)).not_to be_nil
  end

  %i[get_args get_kwargs].each do |accessor|
    it "wraps #{accessor} failure and preserves its cause" do
      selected_entry = entry
      failure = NoMethodError.new("accessor failed")
      allow(Rage::Deferred::Context).to receive(accessor).and_raise(failure)

      expect { selected_entry.retry }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
        expect(error.message).to include(id)
        expect(error.cause).to equal(failure)
      }
      expect(dead_tasks.find_by_id(id)).not_to be_nil
      expect(pending_tasks).to be_empty
    end
  end

  %i[middleware telemetry].each do |layer|
    context "with #{layer}" do
      def intercept_enqueue(layer, &block)
        if layer == :middleware
          enqueue_middleware << [middleware(&block), [], nil]
        else
          allow(tracer).to receive(:span_deferred_task_enqueue, &block)
        end
      end

      it "still flushes and deletes after silent suppression" do
        selected_entry = entry
        intercept_enqueue(layer) { |**| :suppressed }
        expect(backend).to receive(:flush_tasks).ordered.and_call_original
        expect(backend).to receive(:remove_dead_tasks).with(id).ordered.and_call_original

        expect(retry_with_warning(selected_entry)).to eq(true)
        expect(pending_tasks).to be_empty
        expect(dead_tasks.find_by_id(id)).to be_nil
      end

      [false, true].each do |after_enqueue|
        it "retains the dead record when an error occurs #{after_enqueue ? "after" : "before"} queue insertion" do
          selected_entry = entry
          failure = RuntimeError.new("#{layer} failed")
          intercept_enqueue(layer) do |**_, &block|
            block.call if after_enqueue
            raise failure
          end
          expect(backend).not_to receive(:flush_tasks)
          expect(backend).not_to receive(:remove_dead_tasks)

          expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
          expect(dead_tasks.find_by_id(id)).not_to be_nil
          expect(pending_tasks.length).to eq(after_enqueue ? 1 : 0)
        end
      end
    end
  end

  it "preserves multiple-yield enqueue behavior and its nil return" do
    enqueue_middleware << [middleware { |**_, &block| 2.times { block.call }; :ignored }, [], nil]

    expect(RetryableDeadTask.enqueue("ordinary")).to be_nil
    expect(pending_tasks.length).to eq(2)
    expect(retry_with_warning).to eq(true)
    expect(pending_tasks.length).to eq(4)
  end

  it "propagates a pending-storage failure without flush_tasks, removal, or a restart warning" do
    selected_entry = entry
    failure = Errno::ENOSPC.new
    allow(backend).to receive(:add_task).and_raise(failure)
    expect(backend).not_to receive(:flush_tasks)
    expect(backend).not_to receive(:remove_dead_tasks)

    expect {
      expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
    }.to output("").to_stderr
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks).to be_empty
  end

  it "retains the dead record if backpressure prevents queue insertion" do
    selected_entry = entry
    allow(queue).to receive(:apply_backpressure).and_raise(Rage::Deferred::PushTimeout, "queue full")
    queue.instance_variable_set(:@backpressure, true)

    expect { selected_entry.retry }.to raise_error(Rage::Deferred::PushTimeout)
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks).to be_empty
  end

  it "retains the dead record and propagates schedule failure after persistence" do
    selected_entry = entry
    failure = RuntimeError.new("schedule failed")
    allow(queue).to receive(:schedule).and_raise(failure)

    expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks.length).to eq(1)
  end

  it "propagates a flush_tasks failure unchanged without removal or warning" do
    selected_entry = entry
    failure = Errno::EIO.new
    allow(backend).to receive(:flush_tasks).and_raise(failure)
    expect(backend).not_to receive(:remove_dead_tasks)

    expect {
      expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
    }.to output("").to_stderr
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks.length).to eq(1)
  end

  %i[wal directory].each do |operation|
    it "keeps the dead record when #{operation} fsync fails during Disk flush_tasks" do
      selected_entry = entry
      failure = Errno::EIO.new
      if operation == :wal
        storage = backend.instance_variable_get(:@tasks_storage).instance_variable_get(:@storage)
        allow(storage).to receive(:fsync).and_raise(failure)
      else
        directory = instance_double(File)
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(storage_path, File::RDONLY).and_yield(directory)
        allow(directory).to receive(:fsync).and_raise(failure)
      end
      expect(backend).not_to receive(:remove_dead_tasks)

      expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
      expect(dead_tasks.find_by_id(id)).not_to be_nil
      expect(pending_tasks.length).to eq(1)
    end
  end

  it "reports removal failure with the ID, possible duplication, and original cause" do
    selected_entry = entry
    failure = Errno::EACCES.new
    allow(backend).to receive(:remove_dead_tasks).with(id).and_raise(failure)
    expect(backend).to receive(:flush_tasks).and_call_original

    expect {
      expect { selected_entry.retry }.to raise_error(Rage::Deferred::DeadTaskRetryError) { |error|
        expect(error.message).to include(id, "both stores")
        expect(error.cause).to equal(failure)
      }
    }.to output(/server restart is required/).to_stderr
    expect(dead_tasks.find_by_id(id)).not_to be_nil
    expect(pending_tasks.length).to eq(1)
  end

  it "warns once with the ID and restart requirement without payload disclosure or scheduling" do
    store_dead_task(id, args: ["secret argument"], kwargs: { secret: "password" })
    selected_entry = dead_tasks.find_by_id(id)
    expect(Iodine).not_to receive(:run_after)
    expect(Iodine).not_to receive(:task_inc!)
    expect(Iodine).not_to receive(:task_dec!)
    expect(Fiber).not_to receive(:schedule)

    expect { expect(retry_with_warning(selected_entry)).to eq(true) }.to output("").to_stdout
    expect(queue.backlog_size).to eq(0)
    expect(RetryableDeadTask.performed).to be_empty
    expect(pending_tasks.length).to eq(1)
  end

  it "allows two Fiber-interleaved retries to enqueue duplicate work without holding the dead-store lock" do
    first_entry = entry
    second_entry = dead_tasks.find_by_id(id)
    store_dead_task("unrelated")
    other_backend = Rage::Deferred::Backends::Disk.new(path: storage_path, prefix:, fsync_frequency: 100)
    lock_path = storage_path.join("#{prefix}dead_tasks.lock")
    enqueue_middleware << [middleware do |**_, &block|
      lock = File.open(lock_path, "a+b")
      begin
        raise "dead-store lock held across middleware" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      ensure
        lock.close
      end
      Fiber.yield(:checked)
      block.call
    end, [], nil]
    first = Fiber.new { first_entry.retry }
    second = Fiber.new { second_entry.retry }

    expect(first.resume).to eq(:checked)
    expect(second.resume).to eq(:checked)
    expect { expect(first.resume).to eq(true) }.to output(/server restart is required/).to_stderr
    expect { expect(second.resume).to eq(true) }.to output(/server restart is required/).to_stderr
    expect(other_backend.find_dead_task(id)).to be_nil
    expect(other_backend.find_dead_task("unrelated")).not_to be_nil
    expect(pending_tasks.length).to eq(2)
  ensure
    other_backend&.instance_variable_get(:@tasks_storage)&.instance_variable_get(:@storage)&.close
    other_backend&.instance_variable_get(:@dead_tasks_storage)&.instance_variable_get(:@lock_file)&.close
  end

  it "does not let a concurrent deletion cancel work already enqueued" do
    selected_entry = entry
    allow(backend).to receive(:flush_tasks).and_wrap_original do |original|
      expect(pending_tasks.length).to eq(1)
      expect(selected_entry.delete).to eq(true)
      original.call
    end

    expect(retry_with_warning(selected_entry)).to eq(true)
    expect(pending_tasks.length).to eq(1)
    expect(dead_tasks.find_by_id(id)).to be_nil
  end

  %i[first find_by_id block].each do |lookup|
    it "retries an entry retained after #{lookup} releases the traversal" do
      store_dead_task(id)
      selected_entry = case lookup
      when :first then dead_tasks.first
      when :find_by_id then dead_tasks.find_by_id(id)
      when :block
        retained = nil
        dead_tasks.each { |value| retained = value }
        retained
      end

      expect(retry_with_warning(selected_entry)).to eq(true)
      expect(pending_tasks.length).to eq(1)
    end
  end

  it "retries every yielded starting-snapshot entry once across removal compactions" do
    %w[1-1-1 2-1-1 3-1-1].each { |task_id| store_dead_task(task_id, args: [task_id]) }
    attempted = []
    allow(RetryableDeadTask).to receive(:enqueue).and_wrap_original do |original, *args, **kwargs|
      attempted << args.first
      store_dead_task("later-id", args: ["later"]) if attempted.length == 1
      original.call(*args, **kwargs)
    end

    expect { dead_tasks.each(&:retry) }.to output(/server restart is required/).to_stderr

    expect(attempted).to eq(%w[1-1-1 2-1-1 3-1-1])
    expect(dead_tasks.map(&:id)).to eq(["later-id"])
    expect(pending_tasks.length).to eq(3)
  end

  it "skips a rescued enumeration failure, keeps its record, and retries later entries" do
    store_dead_task("first")
    append_serialized_record("broken", "not Marshal".dump)
    store_dead_task("last")

    expect { dead_tasks.each(&:retry) }.to output(
      /ERROR: Can't deserialize the dead-lettered task with id broken: \(TypeError\)/
    ).to_stdout.and output(/server restart is required/).to_stderr

    expect(pending_tasks.length).to eq(2)
    expect(backend.remove_dead_tasks("broken")).to eq(1)
    expect(dead_tasks.to_a).to be_empty
  end

  [ArgumentError, NameError, TypeError].each do |error_class|
    it "returns false after a selected #{error_class} diagnostic without falling back or removing" do
      selected_entry = entry
      original_record = backend.find_dead_task(id)
      marker = Marshal.dump(:selected_failure)
      append_serialized_record(id, marker.dump)
      failure = error_class.new("secret selected failure")
      allow(Marshal).to receive(:load).and_call_original
      allow(Marshal).to receive(:load).with(marker).and_raise(failure)
      expect(RetryableDeadTask).not_to receive(:enqueue)
      expect(backend).not_to receive(:remove_dead_tasks)
      before_retry = dead_tasks_path.binread

      expect { expect(selected_entry.retry).to eq(false) }.to output(
        "ERROR: Can't deserialize the dead-lettered task with id #{id}: (#{error_class}) #{failure.message}\n"
      ).to_stdout.and output("").to_stderr

      expect(dead_tasks_path.binread).to eq(before_retry)
      expect(original_record[:task_class]).to eq("RetryableDeadTask")
      expect(pending_tasks).to be_empty
    end
  end

  it "propagates other selected decoding failures without falling back or removing" do
    selected_entry = entry
    append_serialized_record(id, "not-a-dumped-string")
    before_retry = dead_tasks_path.binread

    expect { selected_entry.retry }.to raise_error(RuntimeError, /dumped string/)
    expect(dead_tasks_path.binread).to eq(before_retry)
    expect(pending_tasks).to be_empty
  end

  it "uses an older valid frame when a newer duplicate has an invalid CRC" do
    selected_entry = entry
    dead_tasks_path.open("ab") { |file| file.write("deadbeef:dead_task:#{id}:bad\n") }

    expect(retry_with_warning(selected_entry)).to eq(true)
    expect(pending_tasks.length).to eq(1)
    expect(dead_tasks.find_by_id(id)).to be_nil
  end

  it "propagates an existence-check lock timeout unchanged" do
    selected_entry = entry
    failure = Rage::Deferred::DeadTasksLockTimeout.new("lookup lock timeout")
    allow(backend).to receive(:find_dead_task).with(id).and_raise(failure)
    expect(RetryableDeadTask).not_to receive(:enqueue)
    expect(backend).not_to receive(:remove_dead_tasks)

    expect { selected_entry.retry }.to raise_error { |raised| expect(raised).to equal(failure) }
    expect(pending_tasks).to be_empty
  end

  context "inside a running server" do
    before do
      logger = double("logger")
      allow(logger).to receive(:with_context).and_yield
      allow(Rage).to receive(:logger).and_return(logger)
      allow(Iodine).to receive(:running?).and_return(true)
      allow(Iodine).to receive(:stopping?).and_return(false)
      allow(Iodine).to receive(:task_inc!)
      allow(Iodine).to receive(:task_dec!)
      allow(Iodine).to receive(:run_after) { |_, &block| block.call }
      allow(Fiber).to receive(:schedule) { |&block| Fiber.new(&block).resume }
    end

    it "executes through the normal queue before flush_tasks and emits no restart warning" do
      selected_entry = entry
      expect(backend).to receive(:flush_tasks) do
        expect(RetryableDeadTask.performed).to eq([[["original"], { key: "value" }]])
      end
      expect(tracer).to receive(:span_deferred_task_process).and_yield

      expect { expect(selected_entry.retry).to eq(true) }.to output("").to_stderr

      expect(queue.backlog_size).to eq(0)
      expect(Iodine).to have_received(:task_inc!).once
      expect(Iodine).to have_received(:task_dec!).once
      expect(pending_tasks).to be_empty
      expect(dead_tasks.find_by_id(id)).to be_nil
    end

    it "allows the same nested mutations during retry and ordinary pending-WAL recovery" do
      shared = ["original"]
      shared << shared
      store_dead_task(id, args: [shared], kwargs: { shared: })
      selected_entry = dead_tasks.find_by_id(id)
      cached_args, cached_kwargs = selected_entry.args, selected_entry.kwargs
      enqueue_middleware << [middleware do |args:, **_, &block|
        args.first << "enqueue middleware"
        block.call
      end, [], nil]
      perform_middleware << [middleware do |args:, kwargs:, **_, &block|
        raise "lost argument alias" unless args.first.equal?(kwargs[:shared])

        args.first << "perform middleware"
        block.call
      end, [], nil]
      RetryableDeadTask.define_method(:perform) do |value, shared:|
        raise "lost nested cycle" unless value.equal?(shared) && value.equal?(value[1])

        value[0].replace("performed")
        value << "perform"
        self.class.performed << value
      end

      expect(selected_entry.retry).to eq(true)
      recovered_shared = ["original"]
      recovered_shared << recovered_shared
      recovered_shared << "enqueue middleware"
      context = Rage::Deferred::Context.build(RetryableDeadTask, [recovered_shared], { shared: recovered_shared })
      recovered_id = backend.add_task(context)
      _, recovered_context, = pending_tasks.find { |task_id,| task_id == recovered_id }
      queue.schedule(recovered_id, recovered_context)

      expect(RetryableDeadTask.performed.length).to eq(2)
      live, recovered = RetryableDeadTask.performed
      expect(live.values_at(0, 2, 3, 4)).to eq(["performed", "enqueue middleware", "perform middleware", "perform"])
      expect(recovered.values_at(0, 2, 3, 4)).to eq(live.values_at(0, 2, 3, 4))
      expect(live[1]).to equal(live)
      expect(recovered[1]).to equal(recovered)
      expect(selected_entry.args).to equal(cached_args)
      expect(selected_entry.kwargs).to equal(cached_kwargs)
      expect(cached_args.first[0]).to eq("original")
      expect(cached_args.first.length).to eq(2)
      expect(pending_tasks).to be_empty
    end
  end
end

RSpec.describe Rage::Deferred::DeadTask, "retry without buffered persistence" do
  it "uses acknowledged enqueue without requiring a flush_tasks method" do
    stub_const("SynchronousRetryTask", Class.new { include Rage::Deferred::Task })
    record = {
      id: "synchronous-id", task_class: "SynchronousRetryTask", attempts: 1,
      enqueued_at: 1, failed_at: 2, exception_class: "RuntimeError", exception_message: "failure",
      backtrace: [], context: Marshal.dump(["SynchronousRetryTask", ["argument"], nil])
    }
    backend = double("synchronous backend", find_dead_task: record)
    entry = Rage::Deferred::DeadTasks.new(backend).find_by_id(record[:id])
    acknowledged = []
    allow(Iodine).to receive(:running?).and_return(false)
    allow(Rage.config.deferred).to receive(:backpressure).and_return(nil)
    allow(Rage::Deferred).to receive(:__queue).and_return(Rage::Deferred::Queue.new(backend))
    chain = Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [], perform_middleware: [])
    allow(Rage::Deferred).to receive(:__middleware_chain).and_return(chain)
    allow(backend).to receive(:add_task) do |context, **|
      acknowledged << context
      "new-id"
    end
    expect(SynchronousRetryTask).to receive(:enqueue).with("argument").and_call_original
    expect(backend).to receive(:remove_dead_tasks).with(record[:id]) do
      expect(acknowledged.length).to eq(1)
      expect(Rage::Deferred::Context.get_task(acknowledged.first)).to equal(SynchronousRetryTask)
      expect(Rage::Deferred::Context.get_args(acknowledged.first)).to eq(["argument"])
      1
    end

    expect(backend).not_to respond_to(:flush_tasks)
    expect { expect(entry.retry).to eq(true) }.to output(/server restart is required/).to_stderr
  end

  it "returns false for Nil without resolving, decoding, persistence, or background work" do
    backend = Rage::Deferred::Backends::Nil.new
    dead_tasks = Rage::Deferred::DeadTasks.new(backend)
    expect(Object).not_to receive(:const_get)
    expect(Marshal).not_to receive(:load)
    expect(backend).not_to receive(:add_task)
    expect(Iodine).not_to receive(:run_after)
    expect(Iodine).not_to receive(:run_every)

    entry = dead_tasks.find_by_id("missing")
    result = entry ? entry.retry : false

    expect(result).to eq(false)
    expect(backend).not_to respond_to(:flush_tasks)
  end

  it "preserves the ordinary public enqueue signature and nil result with Nil storage" do
    stub_const("NilRetryTask", Class.new { include Rage::Deferred::Task })
    backend = Rage::Deferred::Backends::Nil.new
    allow(Iodine).to receive(:running?).and_return(false)
    allow(Rage::Deferred).to receive(:__queue).and_return(Rage::Deferred::Queue.new(backend))
    chain = Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [], perform_middleware: [])
    allow(Rage::Deferred).to receive(:__middleware_chain).and_return(chain)

    expect(NilRetryTask.method(:enqueue).parameters).to eq([
      [:rest, :args], [:key, :delay], [:key, :delay_until], [:keyrest, :kwargs]
    ])
    expect(NilRetryTask.enqueue("argument", keyword: "value")).to be_nil
    expect(backend.pending_tasks).to be_empty
  end
end

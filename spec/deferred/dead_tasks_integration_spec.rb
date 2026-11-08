# frozen_string_literal: true

RSpec.shared_context "with a Disk dead-task store" do
  let(:storage_path) { Pathname.new(Dir.mktmpdir) }
  let(:prefix) { "test_prefix" }
  let(:dead_tasks_path) { storage_path.join("#{prefix}dead_tasks-0") }
  let(:backend) { Rage::Deferred::Backends::Disk.new(path: storage_path, prefix:, fsync_frequency: 100) }
  let(:dead_tasks) { Rage::Deferred::DeadTasks.new(backend) }

  after do
    FileUtils.remove_entry(storage_path)
  end

  def add_dead_task(id)
    backend.add_dead_task(
      id, ["SendWelcomeEmail", [], {}, 0], RuntimeError.new("boom"), task_class: "SendWelcomeEmail", attempts: 3
    )
  end

  # Write a frame-valid record whose payload cannot be decoded.
  def append_undecodable_record(id)
    stub_const("DeletedDuringTraversalArgument", Class.new)
    payload = Marshal.dump({ id:, value: DeletedDuringTraversalArgument.new }).dump
    hide_const("DeletedDuringTraversalArgument")

    entry = "dead_task:#{id}:#{payload}"
    crc = Zlib.crc32(entry).to_s(16).rjust(8, "0")
    dead_tasks_path.open("ab") { |storage| storage.write("#{crc}:#{entry}\n") }
  end

  def stored_ids
    dead_tasks_path.binread.each_line.map { |line| line.split(":", 4)[2] }
  end
end

RSpec.describe Rage::Deferred::DeadTasks do
  include_context "with a Disk dead-task store"

  describe "#delete" do
    it "removes the ids in one backend call" do
      %w[1-1-1 2-2-2 3-3-3 4-4-4].each { |id| add_dead_task(id) }
      allow(backend).to receive(:remove_dead_tasks).and_call_original

      ids = dead_tasks.filter_map { |dead_task| dead_task.id unless dead_task.id == "2-2-2" }

      expect(dead_tasks.delete(ids)).to eq(3)
      expect(backend).to have_received(:remove_dead_tasks).once
      expect(stored_ids).to eq(["2-2-2"])
    end

    context "when two deletions overlap" do
      before(:all) do
        Fiber.set_scheduler(Rage::FiberScheduler.new)
      end

      after(:all) do
        Fiber.set_scheduler(nil)
      end

      it "splits the count in lock order" do
        %w[1-1-1 2-2-2 3-3-3 4-4-4].each { |id| add_dead_task(id) }
        other_dead_tasks = described_class.new(
          Rage::Deferred::Backends::Disk.new(path: storage_path, prefix:, fsync_frequency: 100)
        )
        first_inside_lock = Queue.new
        release_first = Queue.new
        renames = 0

        # Pause the first deletion inside the lock, after it wrote the temp file and before the rename.
        allow(File).to receive(:rename).and_wrap_original do |original, *args|
          renames += 1
          if renames == 1
            first_inside_lock << true
            release_first.pop
          end
          original.call(*args)
        end

        within_reactor do
          first = Fiber.schedule { dead_tasks.delete(%w[1-1-1 2-2-2]) }
          first_inside_lock.pop
          second = Fiber.schedule { other_dead_tasks.delete(%w[2-2-2 3-3-3]) }
          release_first << true
          counts = Fiber.await([first, second])

          -> do
            expect(counts).to eq([2, 1])
            expect(stored_ids).to eq(["4-4-4"])
          end
        rescue => e
          -> { raise e }
        end
      end
    end
  end
end

RSpec.describe Rage::Deferred::DeadTask do
  include_context "with a Disk dead-task store"

  describe "#delete" do
    context "when called during traversal" do
      it "yields a snapshot taken when the traversal starts" do
        %w[1-1-1 2-2-2 3-3-3].each { |id| add_dead_task(id) }
        yielded = []
        results = []

        dead_tasks.each do |dead_task|
          yielded << dead_task.id
          add_dead_task("4-4-4") if dead_task.id == "1-1-1"
          results << dead_task.delete unless dead_task.id == "2-2-2"
        end

        aggregate_failures do
          expect(yielded).to eq(%w[1-1-1 2-2-2 3-3-3])
          expect(results).to eq([true, true])
          expect(stored_ids).to eq(%w[2-2-2 4-4-4])
        end
      end

      context "with an undecodable record" do
        it "prints the error and keeps the record" do
          add_dead_task("1-1-1")
          append_undecodable_record("2-2-2")
          add_dead_task("3-3-3")
          deleted = []

          expect {
            dead_tasks.each { |dead_task| deleted << dead_task.id if dead_task.delete }
          }.to output(
            /\AERROR: Can't deserialize the dead-lettered task with id 2-2-2: \((ArgumentError|NameError)\) .*DeletedDuringTraversalArgument\n\z/
          ).to_stdout

          aggregate_failures do
            expect(deleted).to eq(%w[1-1-1 3-3-3])
            expect(stored_ids).to eq(["2-2-2"])
          end
        end
      end
    end

    context "when another process holds the lock" do
      it "raises DeadTasksLockTimeout" do
        add_dead_task("1-1-1")
        entry = dead_tasks.first
        stub_const("Rage::Deferred::Backends::Disk::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)

        File.open(storage_path.join("#{prefix}dead_tasks.lock"), File::RDWR) do |lock|
          lock.flock(File::LOCK_EX)

          expect { entry.delete }.to raise_error(Rage::Deferred::DeadTasksLockTimeout)
        end

        expect(stored_ids).to eq(["1-1-1"])
      end
    end
  end

  describe "#retry" do
    let!(:task_class) do
      stub_const("RetryableTask", Class.new do
        include Rage::Deferred::Task

        def perform(*, **)
        end
      end)
    end

    before do
      allow(Rage::Deferred).to receive(:__queue).and_return(Rage::Deferred::Queue.new(backend))
    end

    def add_retryable_dead_task(id)
      backend.add_dead_task(
        id, [RetryableTask, ["user"], { force: true }, 3], RuntimeError.new("boom"),
        task_class: "RetryableTask", attempts: 3
      )
    end

    # Run the retry outside a running server, as a console or a Rake task does.
    def retry_outside_server(entry)
      result = nil
      expect { result = entry.retry }.to output.to_stderr
      result
    end

    it "stores a pending task with a new ID and no attempts" do
      add_retryable_dead_task("1-1-1")
      entry = dead_tasks.first

      expect(retry_outside_server(entry)).to be(true)

      pending = backend.pending_tasks
      aggregate_failures do
        expect(pending.length).to eq(1)
        task_id, context = pending.first
        expect(task_id).not_to eq("1-1-1")
        expect(Rage::Deferred::Context.get_task(context)).to eq(RetryableTask)
        expect(Rage::Deferred::Context.get_args(context)).to eq(["user"])
        expect(Rage::Deferred::Context.get_kwargs(context)).to eq({ force: true })
        expect(Rage::Deferred::Context.get_attempts(context)).to be_nil
        expect(stored_ids).to eq([])
      end
    end

    context "with an enqueue middleware that yields" do
      let(:seen_by_middleware) { [] }

      before do
        seen = seen_by_middleware
        middleware = Class.new do
          define_method(:call) do |task_class:, args:, kwargs:, &block|
            seen << [task_class, args, kwargs]
            block.call
          end
        end
        allow(Rage::Deferred).to receive(:__middleware_chain).and_return(
          Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [[middleware, [], nil]], perform_middleware: [])
        )
      end

      after do
        # MiddlewareChain defines its methods on the class; build an empty chain again for later examples.
        Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [], perform_middleware: [])
      end

      it "runs the middleware and the telemetry span" do
        add_retryable_dead_task("1-1-1")
        entry = dead_tasks.first
        allow(Rage::Telemetry.tracer).to receive(:span_deferred_task_enqueue).and_call_original

        retry_outside_server(entry)

        aggregate_failures do
          expect(seen_by_middleware).to eq([[RetryableTask, ["user"], { force: true }]])
          expect(Rage::Telemetry.tracer).to have_received(:span_deferred_task_enqueue).
            with(task_class: RetryableTask, context: kind_of(Array)).once
        end
      end
    end

    context "when a newer duplicate cannot be decoded" do
      it "prints the error and returns false" do
        add_retryable_dead_task("1-1-1")
        entry = dead_tasks.first
        append_undecodable_record("1-1-1")
        result = nil

        expect { result = entry.retry }.to output(
          /\AERROR: Can't deserialize the dead-lettered task with id 1-1-1: /
        ).to_stdout

        aggregate_failures do
          expect(result).to be(false)
          expect(backend.pending_tasks).to eq([])
          expect(stored_ids).to eq(%w[1-1-1 1-1-1])
        end
      end
    end

    context "with a custom enqueue middleware" do
      # Run `body` as the only enqueue middleware; it receives a callable that continues the enqueue.
      def use_enqueue_middleware(&body)
        middleware = Class.new do
          define_method(:call) { |&block| body.call(block) }
        end
        allow(Rage::Deferred).to receive(:__middleware_chain).and_return(
          Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [[middleware, [], nil]], perform_middleware: [])
        )
      end

      after do
        Rage::Deferred::MiddlewareChain.new(enqueue_middleware: [], perform_middleware: [])
      end

      context "when the middleware does not yield" do
        it "removes the record and returns true" do
          add_retryable_dead_task("1-1-1")
          entry = dead_tasks.first
          use_enqueue_middleware { |_proceed| nil }

          aggregate_failures do
            expect(retry_outside_server(entry)).to be(true)
            expect(backend.pending_tasks).to eq([])
            expect(stored_ids).to eq([])
          end
        end
      end

      context "when the middleware deletes the record" do
        it "still enqueues the task" do
          add_retryable_dead_task("1-1-1")
          entry = dead_tasks.first
          other_dead_tasks = Rage::Deferred::DeadTasks.new(
            Rage::Deferred::Backends::Disk.new(path: storage_path, prefix:, fsync_frequency: 100)
          )
          stub_const("Rage::Deferred::Backends::Disk::DeadTasksStorage::LOCK_MAX_ATTEMPTS", 1)
          deleted_inside = nil
          use_enqueue_middleware do |proceed|
            deleted_inside = other_dead_tasks.delete("1-1-1")
            proceed.call
          end

          aggregate_failures do
            expect(retry_outside_server(entry)).to be(true)
            expect(deleted_inside).to eq(1)
            expect(backend.pending_tasks.length).to eq(1)
            expect(stored_ids).to eq([])
          end
        end
      end

      context "when the middleware starts a second retry" do
        it "enqueues the task twice" do
          add_retryable_dead_task("1-1-1")
          first = dead_tasks.first
          second = dead_tasks.first
          second_result = nil
          nested = false
          # Run `second.retry` while `first.retry` is still in progress.
          # The record is not removed yet, so both retries find it and enqueue the task.
          use_enqueue_middleware do |proceed|
            unless nested # `second.retry` passes this middleware too
              nested = true
              second_result = second.retry
            end
            proceed.call
          end
          first_result = nil

          expect { first_result = first.retry }.to output.to_stderr

          aggregate_failures do
            expect([first_result, second_result]).to eq([true, true])
            expect(backend.pending_tasks.length).to eq(2)
            expect(stored_ids).to eq([])
          end
        end
      end
    end

    context "when called during traversal" do
      it "retries the others and keeps an undecodable record" do
        add_retryable_dead_task("1-1-1")
        append_undecodable_record("2-2-2")
        add_retryable_dead_task("3-3-3")

        expect {
          expect { dead_tasks.each(&:retry) }.to output(
            /\AERROR: Can't deserialize the dead-lettered task with id 2-2-2: [^\n]*\n\z/
          ).to_stdout
        }.to output.to_stderr

        aggregate_failures do
          expect(backend.pending_tasks.length).to eq(2)
          expect(stored_ids).to eq(["2-2-2"])
        end
      end
    end

    context "when flush_tasks raises" do
      it "re-raises and keeps the record" do
        add_retryable_dead_task("1-1-1")
        entry = dead_tasks.first
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(storage_path, File::RDONLY).and_raise(Errno::EIO)

        expect { entry.retry }.to raise_error(Errno::EIO)
        expect(stored_ids).to eq(["1-1-1"])
      end
    end
  end
end

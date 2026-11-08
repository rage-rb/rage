# frozen_string_literal: true

RSpec.describe Rage::Deferred::DeadTasks do
  let(:records) do
    [
      {
        id: "1700000001-1-1", task_class: "OlderTask", attempts: 2,
        enqueued_at: 1_700_000_001, failed_at: 1_700_000_011,
        exception_class: "ArgumentError", exception_message: "bad argument",
        backtrace: [], context: Marshal.dump(["OlderTask", [], {}])
      },
      {
        id: "1700000002-1-2", task_class: "MissingTask", attempts: 4,
        enqueued_at: 1_700_000_002, failed_at: 1_700_000_012,
        exception_class: "RuntimeError", exception_message: "secret failure",
        backtrace: ["app/task.rb:1"], context: Marshal.dump(["MissingTask", [], {}])
      }
    ]
  end
  let(:backend) do
    stored_records = records
    Class.new do
      attr_reader :traversal_count, :lookup_count, :removals

      define_method(:initialize) do
        @traversal_count = 0
        @lookup_count = 0
        @removals = []
      end
      define_method(:remove_dead_tasks) do |ids|
        @removals << ids
        removed_ids = Array(ids) & stored_records.map { |record| record[:id] }
        stored_records.reject! { |record| removed_ids.include?(record[:id]) }
        removed_ids.length
      end
      define_method(:each_dead_task) do |&block|
        @traversal_count += 1
        stored_records.each(&block)
        self
      end
      define_method(:find_dead_task) do |id|
        @lookup_count += 1
        stored_records.reverse_each.find { |record| record[:id] == id }
      end
    end.new
  end
  subject(:dead_tasks) { described_class.new(backend) }

  describe "#each" do
    it "returns distinct standard Enumerators without starting backend traversal" do
      expect(backend).not_to receive(:each_dead_task)

      first = dead_tasks.each
      second = dead_tasks.each

      expect(first).to be_a(Enumerator)
      expect(second).to be_a(Enumerator)
      expect(first).not_to equal(second)
      expect(first).not_to respond_to(:close)
    end

    it "keeps both the public and private backend traversal APIs argument-free" do
      expect(dead_tasks.method(:each).parameters).to eq([])
      expect(backend.method(:each_dead_task).parameters).to eq([[:block, :block]])
      expect { dead_tasks.each(limit: 1) }.to raise_error(ArgumentError)

      dead_tasks.each {}

      expect(backend.traversal_count).to eq(1)
    end

    it "yields passive defensive summaries without resolving task classes or contexts" do
      expect(Object).not_to receive(:const_get)
      expect(Marshal).not_to receive(:load)

      entries = dead_tasks.to_a

      expect(entries.map(&:id)).to eq(["1700000001-1-1", "1700000002-1-2"])
      expect(entries.last.task_class).to eq("MissingTask")
      expect(entries.last.attempts).to eq(4)
      expect(entries.last.enqueued_at).to eq(Time.at(1_700_000_002))
      expect(entries.last.failed_at).to eq(Time.at(1_700_000_012))
      expect(entries.last.id).to be_frozen
      expect(entries.last.task_class).to be_frozen
      expect(entries.last.enqueued_at.utc).to equal(entries.last.enqueued_at)
      expect(entries.last.failed_at.gmtime).to equal(entries.last.failed_at)
      entries.last.enqueued_at.localtime("+05:00")
      entries.last.failed_at.localtime("-04:00")
      fresh_entry = dead_tasks.to_a.last

      expect(entries.last.enqueued_at.utc_offset).to eq(5 * 60 * 60)
      expect(entries.last.failed_at.utc_offset).to eq(-4 * 60 * 60)
      expect(fresh_entry.enqueued_at).to eq(Time.at(1_700_000_002))
      expect(fresh_entry.failed_at).to eq(Time.at(1_700_000_012))
      expect(fresh_entry.enqueued_at).not_to equal(entries.last.enqueued_at)
      expect(fresh_entry.failed_at).not_to equal(entries.last.failed_at)
      expect(records.last.values_at(:enqueued_at, :failed_at)).to eq([1_700_000_002, 1_700_000_012])
      expect(entries.last).to respond_to(:args, :kwargs, :exception_class, :exception_message, :backtrace)
    end

    it "retains standard Enumerable find and detect behavior" do
      fallback = -> { :missing }
      unused_fallback = -> { raise "must not run" }

      expect(dead_tasks.find { |entry| entry.attempts == 2 }.task_class).to eq("OlderTask")
      expect(dead_tasks.find(unused_fallback) { |entry| entry.attempts == 2 }.task_class).to eq("OlderTask")
      expect(dead_tasks.detect(fallback) { |entry| entry.attempts == 99 }).to eq(:missing)
      expect(dead_tasks.find).to be_a(Enumerator)
      expect(dead_tasks.detect).to be_a(Enumerator)
    end

    it "uses independent traversals for separate Enumerable operations" do
      dead_tasks.first
      dead_tasks.count

      expect(backend.traversal_count).to eq(2)
      expect(dead_tasks.instance_variables).to eq([:@backend])
      expect(dead_tasks.instance_variable_get(:@backend)).to equal(backend)
    end
  end

  describe "#find_by_id" do
    it "validates an exact String before backend access without coercion" do
      expect(backend).not_to receive(:find_dead_task)

      expect { dead_tasks.find_by_id(:"1700000001-1-1") }.to raise_error(TypeError, /String/)
      expect { dead_tasks.find_by_id(1_700_000_001) }.to raise_error(TypeError, /String/)
      expect(backend.lookup_count).to eq(0)
    end

    it "delegates polymorphically and wraps a matching record" do
      entry = dead_tasks.find_by_id("1700000002-1-2")

      expect(entry).to be_a(Rage::Deferred::DeadTask)
      expect(entry.id).to eq("1700000002-1-2")
      expect(backend.lookup_count).to eq(1)
      expect(dead_tasks.find_by_id("missing")).to be_nil
    end

    it "uses the newest backend record without schema validation or fallback" do
      id = "schema-drift"
      records << records.first.merge(id:, attempts: 1, context: Marshal.dump(["Task", ["older"], {}]))
      records << records.first.merge(id:, task_class: nil, attempts: "unvalidated", context: "not Marshal")

      entry = dead_tasks.find_by_id(id)

      expect(entry.task_class).to be_nil
      expect(entry.attempts).to eq("unvalidated")
      expect { entry.args }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError)
    end

    it "propagates natural entry-construction failures from the selected backend record" do
      invalid_records = [
        [[], TypeError],
        [records.first.merge(backtrace: "not an array"), NoMethodError]
      ]

      invalid_records.each do |record, error_class|
        selected_backend = instance_double("Rage::Deferred::Backend", find_dead_task: record)
        collection = described_class.new(selected_backend)

        expect { collection.find_by_id("selected") }.to raise_error(error_class)
      end
    end

    it "exposes frozen exception metadata without decoding context or resolving the task class" do
      expect(Object).not_to receive(:const_get)
      expect(Marshal).not_to receive(:load)

      entry = dead_tasks.find_by_id("1700000002-1-2")

      expect(entry.exception_class).to eq("RuntimeError")
      expect(entry.exception_message).to eq("secret failure")
      expect(entry.backtrace).to eq(["app/task.rb:1"])
      expect(entry.exception_class).to be_frozen
      expect(entry.exception_message).to be_frozen
      expect(entry.backtrace).to be_frozen
      expect(entry.backtrace.first).to be_frozen
      expect { entry.backtrace << "changed" }.to raise_error(FrozenError)
    end

    it "lazily decodes empty, positional, keyword, and mixed arguments with stable frozen identities" do
      contexts = [
        ["Task", nil, nil],
        ["Task", [["nested"]], nil],
        ["Task", nil, { key: { nested: "value" } }],
        ["Task", [1], { key: 2 }]
      ]
      load_count = 0
      allow(Marshal).to receive(:load).and_wrap_original do |original, *args, **kwargs|
        load_count += 1
        original.call(*args, **kwargs)
      end

      contexts.each_with_index do |context, index|
        record = records.first.merge(id: "context-#{index}", context: Marshal.dump(context))
        records << record
        entry = dead_tasks.find_by_id(record[:id])

        expect(entry.args).to eq(context[1] || [])
        expect(entry.kwargs).to eq(context[2] || {})
        expect(entry.args).to equal(entry.args)
        expect(entry.kwargs).to equal(entry.kwargs)
        expect(entry.args).to be_frozen
        expect(entry.kwargs).to be_frozen
      end

      expect(load_count).to eq(contexts.length)
      expect(dead_tasks.find_by_id("context-1").args.dig(0)).to eq(["nested"])
      expect(dead_tasks.find_by_id("context-2").kwargs.dig(:key, :nested)).to eq("value")
    end

    it "uses the deferred context accessors to extract positional and keyword arguments" do
      context = ["Task", [1], { key: 2 }]
      records << records.first.merge(id: "context-accessors", context: Marshal.dump(context))
      entry = dead_tasks.find_by_id("context-accessors")

      expect(Marshal).to receive(:load).with(instance_of(String), freeze: true).and_call_original
      expect(Rage::Deferred::Context).to receive(:get_args).with(instance_of(Array)).and_call_original
      expect(Rage::Deferred::Context).to receive(:get_kwargs).with(instance_of(Array)).and_call_original

      expect(entry.args).to eq([1])
      expect(entry.kwargs).to eq({ key: 2 })
    end

    it "normalizes missing argument slots through the context accessors" do
      records << records.first.merge(id: "missing-slots", context: Marshal.dump(["Task"]))
      entry = dead_tasks.find_by_id("missing-slots")

      expect(entry.args).to eq([])
      expect(entry.kwargs).to eq({})
      expect(entry.args).to be_frozen
      expect(entry.kwargs).to be_frozen
      expect(entry.args).to equal(entry.args)
      expect(entry.kwargs).to equal(entry.kwargs)
    end

    it "freezes nested argument graphs defensively" do
      shared = ["secret"]
      shared << shared
      records << records.first.merge(
        id: "nested", context: Marshal.dump(["Task", [shared], { shared: }])
      )
      entry = dead_tasks.find_by_id("nested")

      expect(entry.args.first).to equal(entry.kwargs[:shared])
      expect(entry.args.first).to equal(entry.args.first.last)
      expect(entry.args.first).to be_frozen
      expect(entry.args.first.first).to be_frozen
      expect { entry.args.first << "changed" }.to raise_error(FrozenError)
      expect { entry.kwargs[:shared].first.replace("changed") }.to raise_error(FrozenError)
    end

    it "raises the dedicated error with id and cause, without caching a failed decode" do
      records << records.first.merge(id: "broken", context: "not Marshal")
      entry = dead_tasks.find_by_id("broken")

      2.times do
        expect { entry.args }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
          expect(error.message).to include("broken")
          expect(error.cause).to be_a(TypeError)
        }
      end
      expect(entry.id).to eq("broken")
      expect(entry.exception_class).to eq("ArgumentError")
      expect(dead_tasks.find_by_id("broken")).not_to be_nil
    end

    it "translates context accessor failures without caching a partial extraction" do
      records << records.first.merge(id: "accessor-failure", context: Marshal.dump(["Task", [1], { key: 2 }]))
      entry = dead_tasks.find_by_id("accessor-failure")
      args_calls = 0
      kwargs_calls = 0

      allow(Rage::Deferred::Context).to receive(:get_args).and_wrap_original do |method, context|
        args_calls += 1
        method.call(context)
      end
      allow(Rage::Deferred::Context).to receive(:get_kwargs).and_wrap_original do |method, context|
        kwargs_calls += 1
        raise NoMethodError, "context accessor failed" if kwargs_calls == 1

        method.call(context)
      end

      expect { entry.args }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
        expect(error.message).to include("accessor-failure")
        expect(error.cause).to be_a(NoMethodError)
      }
      expect(entry.kwargs).to eq({ key: 2 })
      expect(entry.args).to eq([1])
      expect(args_calls).to eq(2)
      expect(kwargs_calls).to eq(2)
    end

    it "keeps missing referenced constants recoverable through metadata" do
      stub_const("TemporaryDeadTaskArgument", Class.new)
      dumped = Marshal.dump(["Task", [TemporaryDeadTaskArgument.new], {}])
      hide_const("TemporaryDeadTaskArgument")
      records << records.first.merge(id: "missing-constant", context: dumped)
      entry = dead_tasks.find_by_id("missing-constant")

      expect(entry.task_class).to eq("OlderTask")
      expect { entry.args }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
        expect(error.cause).to be_a(ArgumentError).or be_a(NameError)
      }
    end

    it "retries decoding after a missing referenced constant is restored" do
      stub_const("RestorableDeadTaskArgument", Class.new)
      dumped = Marshal.dump(["Task", [RestorableDeadTaskArgument.new], {}])
      hide_const("RestorableDeadTaskArgument")
      records << records.first.merge(id: "restorable-constant", context: dumped)
      entry = dead_tasks.find_by_id("restorable-constant")

      expect { entry.args }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError)

      stub_const("RestorableDeadTaskArgument", Class.new)
      expect(entry.args.first).to be_a(RestorableDeadTaskArgument)
    end
  end

  describe "#delete" do
    context "with a String id" do
      it "returns the removed count" do
        expect(dead_tasks.delete("1700000001-1-1")).to eq(1)
        expect(backend.removals).to eq([["1700000001-1-1"]])
      end
    end

    context "with an Array of ids" do
      it "removes them in one backend call" do
        expect(dead_tasks.delete(["1700000001-1-1", "1700000002-1-2"])).to eq(2)
        expect(backend.removals).to eq([["1700000001-1-1", "1700000002-1-2"]])
      end

      it "passes each id once" do
        result = dead_tasks.delete(["1700000002-1-2", "missing", "1700000002-1-2"])

        expect(result).to eq(1)
        expect(backend.removals).to eq([["1700000002-1-2", "missing"]])
      end
    end

    context "with an empty Array" do
      it "returns 0 without a backend call" do
        expect(dead_tasks.delete([])).to eq(0)
        expect(backend.removals).to eq([])
      end
    end

    context "with an invalid id" do
      it "raises TypeError for a nested Array without a backend call" do
        expect { dead_tasks.delete([["1700000001-1-1"]]) }.to raise_error(TypeError)
        expect(backend.removals).to eq([])
      end

      it "raises TypeError for a non-String id without a backend call" do
        expect { dead_tasks.delete(nil) }.to raise_error(TypeError)
        expect(backend.removals).to eq([])
      end

      it "removes nothing if one member is invalid" do
        expect { dead_tasks.delete(["1700000001-1-1", :"1700000002-1-2"]) }.to raise_error(TypeError)
        expect(backend.removals).to eq([])
        expect(records.map { |record| record[:id] }).to eq(["1700000001-1-1", "1700000002-1-2"])
      end
    end
  end
end

RSpec.describe Rage::Deferred::DeadTask do
  let(:id) { "1700000003-1-3" }
  let(:task_class_name) { "RetryableTask" }
  let(:stored_context) { Marshal.dump(["RetryableTask", ["user"], { force: true }]) }
  let(:record) do
    {
      id:, task_class: task_class_name, attempts: 5,
      enqueued_at: 1_700_000_003, failed_at: 1_700_000_013,
      exception_class: "RuntimeError", exception_message: "boom",
      backtrace: [], context: stored_context
    }
  end
  let(:entry) { described_class.send(:new, record, backend) }

  describe "#delete" do
    let(:backend) { double("backend", remove_dead_tasks: 1) }

    it "returns true without a lookup" do
      expect(entry.delete).to be(true)
      expect(backend).to have_received(:remove_dead_tasks).with(id).once
    end

    context "when the record is already gone" do
      let(:backend) { double("backend", remove_dead_tasks: 0) }

      it "returns false" do
        expect(entry.delete).to be(false)
      end
    end

    context "with an entry from find_by_id" do
      let(:backend) { double("backend", find_dead_task: record, remove_dead_tasks: 1) }

      it "deletes through the same backend" do
        entry = Rage::Deferred::DeadTasks.new(backend).find_by_id(id)

        expect(entry.delete).to be(true)
        expect(backend).to have_received(:remove_dead_tasks).with(id).once
      end
    end
  end

  describe "#retry" do
    let(:backend) { double("backend", find_dead_task: record, flush_tasks: nil, remove_dead_tasks: 1) }
    # A backend that allows only the lookup: a flush or a removal fails the example.
    let(:lookup_only_backend) { double("backend", find_dead_task: record) }

    let!(:task_class) do
      stub_const("RetryableTask", Class.new do
        include Rage::Deferred::Task

        def perform(*, **)
        end
      end)
    end

    before do
      allow(task_class).to receive(:enqueue)
      allow(Iodine).to receive(:running?).and_return(true)
    end

    context "when the record is gone" do
      let(:backend) { double("backend", find_dead_task: nil) }

      it "returns false without enqueue" do
        expect(entry.retry).to be(false)
        expect(task_class).not_to have_received(:enqueue)
      end
    end

    context "when the record exists" do
      it "enqueues, flushes, then removes the record" do
        expect(backend).to receive(:find_dead_task).with(id).once.ordered.and_return(record)
        expect(task_class).to receive(:enqueue).with("user", force: true).once.ordered
        expect(backend).to receive(:flush_tasks).once.ordered
        expect(backend).to receive(:remove_dead_tasks).with(id).once.ordered.and_return(1)

        expect(entry.retry).to be(true)
      end
    end

    context "without stored arguments" do
      let(:stored_context) { Marshal.dump(["RetryableTask", nil, nil]) }

      it "enqueues with no arguments" do
        expect(entry.retry).to be(true)
        expect(task_class).to have_received(:enqueue).with(no_args)
      end
    end

    context "when the backend has no flush_tasks" do
      let(:backend) { double("backend", find_dead_task: record) }

      it "removes the record after enqueue" do
        expect(task_class).to receive(:enqueue).once.ordered
        expect(backend).to receive(:remove_dead_tasks).with(id).once.ordered.and_return(1)

        expect(entry.retry).to be(true)
      end
    end

    context "when the removal finds no record" do
      let(:backend) { double("backend", find_dead_task: record, flush_tasks: nil, remove_dead_tasks: 0) }

      it "returns true" do
        expect(entry.retry).to be(true)
      end
    end

    context "when the task class does not exist" do
      let(:task_class_name) { "MissingRetryableTask" }
      let(:backend) { lookup_only_backend }

      it "raises DeadTaskRetryError with a NameError cause, no enqueue" do
        expect { entry.retry }.to raise_error(Rage::Deferred::DeadTaskRetryError) { |error|
          expect(error.message).to include(id)
          expect(error.cause).to be_a(NameError)
        }
      end
    end

    context "when the task class is not a deferred task" do
      let(:task_class_name) { "PlainRetryableClass" }
      let(:backend) { lookup_only_backend }

      it "raises DeadTaskRetryError without enqueue" do
        stub_const("PlainRetryableClass", Class.new)

        expect { entry.retry }.to raise_error(Rage::Deferred::DeadTaskRetryError, /#{id}/)
      end
    end

    context "when the stored context cannot be decoded" do
      let(:stored_context) { "not a Marshal dump" }
      let(:backend) { lookup_only_backend }

      it "raises DeadTaskContextDeserializationError without enqueue" do
        expect { entry.retry }.to raise_error(Rage::Deferred::DeadTaskContextDeserializationError) { |error|
          expect(error.message).to include(id)
          expect(error.cause).to be_a(TypeError)
        }
        expect(task_class).not_to have_received(:enqueue)
      end
    end

    context "when enqueue raises" do
      let(:backend) { lookup_only_backend }

      it "re-raises without flush and keeps the record" do
        error = Rage::Deferred::PushTimeout.new("queue is full")
        allow(task_class).to receive(:enqueue).and_raise(error)

        expect { entry.retry }.to raise_error { |raised| expect(raised).to equal(error) }
      end
    end

    context "when flush_tasks raises" do
      let(:backend) { lookup_only_backend }

      it "re-raises and keeps the record" do
        error = Errno::EIO.new("fsync")
        allow(backend).to receive(:flush_tasks).and_raise(error)

        expect { entry.retry }.to raise_error { |raised| expect(raised).to equal(error) }
      end
    end

    context "with shared references and a cycle" do
      let(:stored_context) do
        shared = ["nested"]
        cycle = []
        cycle << cycle
        Marshal.dump(["RetryableTask", [shared, cycle], { same: shared }])
      end
      let(:replayed) { [] }

      before do
        received = replayed
        allow(task_class).to receive(:enqueue) do |*args, **kwargs|
          received << args << kwargs
          args[0] << "changed by enqueue"
        end
      end

      it "replays a mutable copy of the graph" do
        entry.retry
        args, kwargs = replayed

        aggregate_failures do
          expect(args[0]).to eq(["nested", "changed by enqueue"])
          expect(args[0]).not_to be_frozen
          expect(kwargs[:same]).to equal(args[0])
          expect(args[1][0]).to equal(args[1])
        end
      end

      it "keeps the frozen inspection cache" do
        inspected_args = entry.args
        inspected_kwargs = entry.kwargs

        entry.retry

        aggregate_failures do
          expect(entry.args).to equal(inspected_args)
          expect(entry.kwargs).to equal(inspected_kwargs)
          expect(entry.args[0]).to eq(["nested"])
          expect(entry.args[0]).to be_frozen
          expect(replayed[0][0]).not_to equal(inspected_args[0])
        end
      end
    end

    context "when the record was replaced" do
      let(:replacement) do
        record.merge(task_class: "OtherTask", context: Marshal.dump(["OtherTask", ["other"], {}]))
      end
      let(:backend) { double("backend", find_dead_task: replacement, flush_tasks: nil, remove_dead_tasks: 1) }

      it "replays the entry's own class and args" do
        entry.retry

        expect(task_class).to have_received(:enqueue).with("user", force: true).once
      end

      it "removes the new record" do
        expect(entry.retry).to be(true)
        expect(backend).to have_received(:remove_dead_tasks).with(id).once
      end
    end

    context "when the server is not running" do
      it "warns that a restart is needed" do
        allow(Iodine).to receive(:running?).and_return(false)

        expect { entry.retry }.to output("Dead task #{id} was retried; server restart is required.\n").to_stderr
      end
    end

    context "when the server is running" do
      it "does not warn" do
        expect { entry.retry }.not_to output.to_stderr
      end
    end

    context "when the removal raises" do
      let(:backend) { double("backend", find_dead_task: record, flush_tasks: nil) }

      it "raises DeadTaskRetryError with the cause" do
        cause = Errno::EIO.new("rename")
        allow(backend).to receive(:remove_dead_tasks).and_raise(cause)

        expect { entry.retry }.to raise_error(Rage::Deferred::DeadTaskRetryError) { |error|
          expect(error.message).to include(id)
          expect(error.cause).to equal(cause)
        }
      end
    end
  end
end

RSpec.describe Rage::Deferred, ".dead_tasks" do
  before do
    @memoized_values = {}
    %i[@__backend @__dead_tasks @__queue].each do |name|
      if described_class.instance_variable_defined?(name)
        @memoized_values[name] = described_class.instance_variable_get(name)
        described_class.remove_instance_variable(name)
      end
    end
  end

  after do
    %i[@__backend @__dead_tasks @__queue].each do |name|
      described_class.remove_instance_variable(name) if described_class.instance_variable_defined?(name)
      described_class.instance_variable_set(name, @memoized_values[name]) if @memoized_values.key?(name)
    end
  end

  let(:backend) { instance_double("Rage::Deferred::Backend") }

  before do
    allow(Rage.config.deferred).to receive(:backend).and_return(backend)
  end

  it "resolves the configured backend once and passes it directly to one memoized collection" do
    expect(Rage::Deferred::DeadTasks).to receive(:new).with(backend).once.and_call_original
    expect(backend).not_to receive(:each_dead_task)

    first = described_class.dead_tasks

    expect(described_class.dead_tasks).to equal(first)
    expect(first.instance_variable_get(:@backend)).to equal(backend)
    expect(Rage.config.deferred).to have_received(:backend).once
  end

  it "does not start traversal when creating unadvanced Enumerators" do
    expect(backend).not_to receive(:each_dead_task)

    first = described_class.dead_tasks.each
    second = described_class.dead_tasks.each

    expect(first).to be_a(Enumerator)
    expect(second).not_to equal(first)
  end

  it "shares the backend when the queue initializes it first" do
    queue = described_class.__queue
    collection = described_class.dead_tasks

    expect(queue.instance_variable_get(:@backend)).to equal(backend)
    expect(collection.instance_variable_get(:@backend)).to equal(backend)
    expect(Rage.config.deferred).to have_received(:backend).once
  end

  it "shares the backend when the collection initializes it first" do
    collection = described_class.dead_tasks
    queue = described_class.__queue

    expect(collection.instance_variable_get(:@backend)).to equal(backend)
    expect(queue.instance_variable_get(:@backend)).to equal(backend)
    expect(Rage.config.deferred).to have_received(:backend).once
  end
end

RSpec.describe Rage::Deferred::Backends::Nil, "dead-task traversal" do
  it "is empty without creating persistence or background activity" do
    backend = described_class.new
    collection = Rage::Deferred::DeadTasks.new(backend)

    expect(backend.method(:each_dead_task).parameters).to eq([])
    expect(collection.to_a).to eq([])
  end

  it "returns 0 from DeadTasks#delete" do
    collection = Rage::Deferred::DeadTasks.new(described_class.new)

    expect(collection.delete("1700000001-1-1")).to eq(0)
    expect(collection.delete(["1700000001-1-1", "1700000002-1-2"])).to eq(0)
  end
end

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
      attr_reader :traversal_count, :lookup_count

      define_method(:initialize) do
        @traversal_count = 0
        @lookup_count = 0
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
end

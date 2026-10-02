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
      attr_reader :traversal_count

      define_method(:initialize) { @traversal_count = 0 }
      define_method(:each_dead_task) do |&block|
        @traversal_count += 1
        stored_records.each(&block)
        self
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
      expect { dead_tasks.each(batch_size: 1) }.to raise_error(ArgumentError)

      dead_tasks.each {}

      expect(backend.traversal_count).to eq(1)
    end

    it "yields passive immutable summaries without resolving task classes or contexts" do
      stub_const("MissingTask", Class.new)
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
      expect(entries.last.enqueued_at).to be_frozen
      expect(entries.last).not_to respond_to(:args)
      expect(entries.last).not_to respond_to(:delete)
      expect(entries.last).not_to respond_to(:retry)
      expect(entries.last.instance_variables).not_to include(:@backend, :@dead_tasks, :@operation_delegate)
    end

    it "retains standard Enumerable find and detect behavior" do
      fallback = -> { :missing }

      expect(dead_tasks.find { |entry| entry.attempts == 2 }.task_class).to eq("OlderTask")
      expect(dead_tasks.detect(fallback) { |entry| entry.attempts == 99 }).to eq(:missing)
      expect(dead_tasks.find).to be_a(Enumerator)
    end

    it "uses independent traversals for separate Enumerable operations" do
      dead_tasks.first
      dead_tasks.count

      expect(backend.traversal_count).to eq(2)
      expect(dead_tasks.instance_variables).to eq([:@backend])
      expect(dead_tasks.instance_variable_get(:@backend)).to equal(backend)
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

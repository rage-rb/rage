RSpec.describe Rage::Deferred::Context do
  describe ".build" do
    let(:task) { :dummy_task }
    let(:args) { [1, 2, 3] }
    let(:kwargs) { { key: "value" } }

    after do
      Thread.current[:rage_logger] = nil
    end

    context "when Thread.current[:rage_logger] is not set" do
      it "builds context with nil request_id" do
        context = described_class.build(task, args, kwargs)
        expect(context[0]).to eq(task)
        expect(context[1]).to eq(args)
        expect(context[2]).to eq(kwargs)
        expect(context[3]).to be_nil
        expect(context[4]).to be_nil
      end

      it "returns nil for args and kwargs if empty" do
        context = described_class.build(task, [], {})
        expect(context[1]).to be_nil
        expect(context[2]).to be_nil
      end
    end

    context "when Thread.current[:rage_logger] is set" do
      before do
        Thread.current[:rage_logger] = { tags: ["req-123", "test"] }
      end

      it "builds context including log tags" do
        context = described_class.build(task, args, kwargs)
        expect(context[4]).to eq(["req-123", "test"])
      end
    end
  end

  describe ".get_task" do
    it "returns the task from context" do
      context = [:my_task, nil, nil, nil, nil]
      expect(described_class.get_task(context)).to eq(:my_task)
    end
  end

  describe ".get_args" do
    it "returns the args from context" do
      context = [nil, [10, 20], nil, nil, nil]
      expect(described_class.get_args(context)).to eq([10, 20])
    end
  end

  describe ".get_kwargs" do
    it "returns the kwargs from context" do
      context = [nil, nil, { a: 1 }, nil, nil]
      expect(described_class.get_kwargs(context)).to eq({ a: 1 })
    end
  end

  describe ".get_attempts" do
    it "returns the attempts from context" do
      context = [nil, nil, nil, 2, nil]
      expect(described_class.get_attempts(context)).to eq(2)
    end
  end

  describe ".get_log_tags" do
    it "returns log tags from context" do
      context = [nil, nil, nil, nil, ["tag-1", "tag-2"]]
      expect(described_class.get_log_tags(context)).to eq(["tag-1", "tag-2"])
    end
  end

  describe ".get_log_context" do
    it "returns log tags from context" do
      context = [nil, nil, nil, nil, nil, { test: true }]
      expect(described_class.get_log_context(context)).to eq({ test: true })
    end
  end

  describe ".inc_attempts" do
    it "increments attempts when attempts is nil" do
      context = [nil, nil, nil, nil, nil]
      described_class.inc_attempts(context)
      expect(context[3]).to eq(1)
    end

    it "increments attempts when attempts is set" do
      context = [nil, nil, nil, 3, nil]
      described_class.inc_attempts(context)
      expect(context[3]).to eq(4)
    end
  end

  describe ".get_user_context" do
    subject { described_class.get_user_context(context) }

    context "with no context" do
      let(:context) { [nil, nil, nil, nil, nil, nil, nil] }

      it "returns nil" do
        expect(subject).to be_nil
      end
    end

    context "with context" do
      let(:context) { [nil, nil, nil, nil, nil, nil, :test_context] }

      it "returns nil" do
        expect(subject).to eq(:test_context)
      end
    end
  end

  describe ".get_or_create_user_context" do
    subject { described_class.get_or_create_user_context(context) }

    context "with no context" do
      let(:context) { [nil, nil, nil, nil, nil, nil, nil] }

      it "returns nil" do
        expect(subject).to eq({})
      end

      it "changes context" do
        expect { subject }.to change { context.last }
      end
    end

    context "with context" do
      let(:context) { [nil, nil, nil, nil, nil, nil, :test_context] }

      it "returns nil" do
        expect(subject).to eq(:test_context)
      end
    end
  end
end

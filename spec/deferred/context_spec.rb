RSpec.describe Rage::Deferred::Context do
  describe ".build" do
    let(:task) { :dummy_task }
    let(:args) { [1, 2, 3] }
    let(:kwargs) { { key: "value" } }

    after do
      Fiber[:__rage_logger_tags] = nil
      Fiber[:__rage_logger_context] = nil
    end

    context "when rage_logger is not set" do
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

    context "when rage_logger is set" do
      before do
        Fiber[:__rage_logger_tags] = ["req-123", "test"]
        Fiber[:__rage_logger_context] = { user_id: 42 }
      end

      it "builds context including log tags" do
        context = described_class.build(task, args, kwargs)
        expect(context[4]).to eq(["req-123", "test"])
      end

      it "builds context including log context" do
        context = described_class.build(task, args, kwargs)
        expect(context[5]).to eq({ user_id: 42 })
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

  describe ".capture_current_attributes" do
    context "when ActiveSupport is not loaded" do
      before { hide_const("ActiveSupport::CurrentAttributes") if defined?(ActiveSupport::CurrentAttributes) }

      it "returns nil" do
        expect(described_class.capture_current_attributes).to be_nil
      end
    end

    context "when ActiveSupport::CurrentAttributes exists but has no subclasses" do
      before do
        stub_const("ActiveSupport::CurrentAttributes", Class.new {
          def self.descendants
            []
          end
        })
      end

      it "returns nil" do
        expect(described_class.capture_current_attributes).to be_nil
      end
    end

    context "when there are subclasses with attributes" do
      let(:subclass) do
        Class.new do
          def self.name
            "Current"
          end

          def self.attributes
            { user_id: 42, tenant: "acme" }
          end
        end
      end

      before do
        stub_const("ActiveSupport::CurrentAttributes", Class.new)
        allow(ActiveSupport::CurrentAttributes).to receive(:descendants).and_return([subclass])
      end

      it "captures the subclass and a duplicated attribute hash" do
        snapshots = described_class.capture_current_attributes
        expect(snapshots).to eq([[subclass, { user_id: 42, tenant: "acme" }]])
      end

      it "returns a duplicated hash so later mutation does not leak into the snapshot" do
        snapshots = described_class.capture_current_attributes
        # Why: if we captured the live hash reference, a `Current.reset` in the
        # parent fiber after enqueue would wipe the snapshot before the task runs.
        expect(snapshots.first.last).not_to equal(subclass.attributes)
      end
    end

    context "when a subclass has no attributes set" do
      let(:empty_subclass) do
        Class.new do
          def self.name
            "EmptyCurrent"
          end

          def self.attributes
            {}
          end
        end
      end

      before do
        stub_const("ActiveSupport::CurrentAttributes", Class.new)
        allow(ActiveSupport::CurrentAttributes).to receive(:descendants).and_return([empty_subclass])
      end

      it "excludes the empty subclass and returns nil when nothing worth capturing" do
        expect(described_class.capture_current_attributes).to be_nil
      end
    end
  end

  describe ".get_current_attributes" do
    it "returns index 7 of the context" do
      context = [nil, nil, nil, nil, nil, nil, nil, :ca_snapshot]
      expect(described_class.get_current_attributes(context)).to eq(:ca_snapshot)
    end

    it "returns nil when the context array has no index 7 (backward compatible with pre-CA contexts)" do
      context = [nil, nil, nil, nil, nil, nil, nil]
      expect(described_class.get_current_attributes(context)).to be_nil
    end
  end
end

RSpec.describe Rage::Deferred::Metadata do
  describe ".build" do
    let(:task)   { :dummy_task }
    let(:args)   { [1, 2, 3] }
    let(:kwargs) { { key: "value" } }

    after do
      Thread.current[:rage_logger] = nil
    end

    context "when Thread.current[:rage_logger] is not set" do
      it "builds metadata with nil request_id" do
        metadata = described_class.build(task, args, kwargs)
        expect(metadata[0]).to eq(task)
        expect(metadata[1]).to eq(args)
        expect(metadata[2]).to eq(kwargs)
        expect(metadata[3]).to be_nil
        expect(metadata[4]).to be_nil
      end

      it "returns nil for args and kwargs if empty" do
        metadata = described_class.build(task, [], {})
        expect(metadata[1]).to be_nil
        expect(metadata[2]).to be_nil
      end
    end

    context "when Thread.current[:rage_logger] is set" do
      before do
        Thread.current[:rage_logger] = { tags: ["req-123"] }
      end

      it "builds metadata including request_id" do
        metadata = described_class.build(task, args, kwargs)
        expect(metadata[4]).to eq("req-123")
      end
    end
  end

  describe ".get_task" do
    it "returns the task from metadata" do
      metadata = [:my_task, nil, nil, nil, nil]
      expect(described_class.get_task(metadata)).to eq(:my_task)
    end
  end

  describe ".get_args" do
    it "returns the args from metadata" do
      metadata = [nil, [10, 20], nil, nil, nil]
      expect(described_class.get_args(metadata)).to eq([10, 20])
    end
  end

  describe ".get_kwargs" do
    it "returns the kwargs from metadata" do
      metadata = [nil, nil, { a: 1 }, nil, nil]
      expect(described_class.get_kwargs(metadata)).to eq({ a: 1 })
    end
  end

  describe ".get_attempts" do
    it "returns the attempts from metadata" do
      metadata = [nil, nil, nil, 2, nil]
      expect(described_class.get_attempts(metadata)).to eq(2)
    end
  end

  describe ".get_request_id" do
    it "returns the request id from metadata" do
      metadata = [nil, nil, nil, nil, "req-456"]
      expect(described_class.get_request_id(metadata)).to eq("req-456")
    end
  end

  describe ".inc_attempts" do
    it "increments attempts when attempts is nil" do
      metadata = [nil, nil, nil, nil, nil]
      described_class.inc_attempts(metadata)
      expect(metadata[3]).to eq(1)
    end

    it "increments attempts when attempts is set" do
      metadata = [nil, nil, nil, 3, nil]
      described_class.inc_attempts(metadata)
      expect(metadata[3]).to eq(4)
    end
  end
end

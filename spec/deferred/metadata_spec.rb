# frozen_string_literal: true

RSpec.describe Rage::Deferred::Metadata do
  subject { described_class }

  let(:task) { double }
  let(:context) { Rage::Deferred::Context.build(task, [], {}) }

  before do
    Fiber[Rage::Deferred::Task::CONTEXT_KEY] = context
  end

  describe ".attempts" do
    context "on the first attempt" do
      it "returns 1" do
        expect(subject.attempts).to eq(1)
      end
    end

    context "on the second attempt" do
      before do
        Rage::Deferred::Context.inc_attempts(context)
      end

      it "returns 2" do
        expect(subject.attempts).to eq(2)
      end
    end
  end

  describe ".retries" do
    context "on the first attempt" do
      it "returns 0" do
        expect(subject.retries).to eq(0)
      end
    end

    context "on the second attempt" do
      before do
        Rage::Deferred::Context.inc_attempts(context)
      end

      it "returns 1" do
        expect(subject.retries).to eq(1)
      end
    end
  end

  describe ".retrying?" do
    context "on the first attempt" do
      it "returns false" do
        expect(subject).not_to be_retrying
      end
    end

    context "on the second attempt" do
      before do
        Rage::Deferred::Context.inc_attempts(context)
      end

      it "returns true" do
        expect(subject).to be_retrying
      end
    end
  end

  describe "will_retry?" do
    before do
      Rage::Deferred::Context.inc_attempts(context)
    end

    it "delegates to Task.__should_retry?" do
      expect(task).to receive(:__should_retry?).with(2).and_return(:should_retry_result)
      expect(subject.will_retry?).to eq(:should_retry_result)
    end
  end
end

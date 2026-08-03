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

    it "delegates to Task.__next_retry_in" do
      expect(task).to receive(:__next_retry_in).with(2, nil).and_return(10)
      expect(subject.will_retry?).to eq(true)
    end

    it "returns false when __next_retry_in returns nil" do
      expect(task).to receive(:__next_retry_in).with(2, nil).and_return(nil)
      expect(subject.will_retry?).to eq(false)
    end
  end

  describe ".will_retry_in" do
    before do
      Rage::Deferred::Context.inc_attempts(context)
    end

    it "returns the retry interval when retries remain" do
      expect(task).to receive(:__next_retry_in).with(2, nil).and_return(15)
      expect(subject.will_retry_in).to eq(15)
    end

    it "returns nil when no retries remain" do
      expect(task).to receive(:__next_retry_in).with(2, nil).and_return(nil)
      expect(subject.will_retry_in).to be_nil
    end
  end
end

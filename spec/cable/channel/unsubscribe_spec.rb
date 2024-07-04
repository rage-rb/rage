# frozen_string_literal: true

module CableChannelUnsubscribeSpec
  class TestChannel < Rage::Cable::Channel
    def unsubscribed
      verifier.unsubscribed
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    before_unsubscribe do
      verifier.before_unsubscribe
    end

    after_unsubscribe do
      verifier.after_unsubscribe
    end

    def unsubscribed
      verifier.unsubscribed
    end
  end

  class TestChannel3 < Rage::Cable::Channel
    before_unsubscribe do
      verifier.before_unsubscribe
    end

    after_unsubscribe do
      verifier.after_unsubscribe
    end
  end

  class TestChannel4 < TestChannel3
    def unsubscribed
      verifier.unsubscribed
    end
  end

  class TestChannel5 < Rage::Cable::Channel
    before_unsubscribe :verify_before_unsubscribe, if: -> { false }
    before_unsubscribe :verify_after_unsubscribe, if: -> { true }

    private

    def verify_before_unsubscribe
      verifier.before_unsubscribe
    end

    def verify_after_unsubscribe
      verifier.after_unsubscribe
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  subject { klass.tap(&:__register_actions).new(nil, nil, nil).__run_action(:unsubscribed) }

  let(:verifier) { double }

  before do
    allow_any_instance_of(Rage::Cable::Channel).to receive(:verifier).and_return(verifier)
  end

  context "with the unsubscribed callback" do
    let(:klass) { CableChannelUnsubscribeSpec::TestChannel }

    it "correctly runs the unsubscribed callback" do
      expect(verifier).to receive(:unsubscribed)
      subject
    end
  end

  context "with before/after unsubscribe" do
    let(:klass) { CableChannelUnsubscribeSpec::TestChannel2 }

    it "correctly runs the unsubscribed callback" do
      expect(verifier).to receive(:before_unsubscribe)
      expect(verifier).to receive(:unsubscribed)
      expect(verifier).to receive(:after_unsubscribe)
      subject
    end
  end

  context "with implicit unsubscribed callback" do
    let(:klass) { CableChannelUnsubscribeSpec::TestChannel3 }

    it "correctly runs the unsubscribed callback" do
      expect(verifier).to receive(:before_unsubscribe)
      expect(verifier).to receive(:after_unsubscribe)
      subject
    end
  end

  context "with inheritance" do
    let(:klass) { CableChannelUnsubscribeSpec::TestChannel4 }

    it "correctly runs the unsubscribed callback" do
      expect(verifier).to receive(:before_unsubscribe)
      expect(verifier).to receive(:unsubscribed)
      expect(verifier).to receive(:after_unsubscribe)
      subject
    end
  end

  context "with conditionals" do
    let(:klass) { CableChannelUnsubscribeSpec::TestChannel5 }

    it "correctly runs the unsubscribed callback" do
      expect(verifier).not_to receive(:before_unsubscribe)
      expect(verifier).to receive(:after_unsubscribe)
      subject
    end
  end
end

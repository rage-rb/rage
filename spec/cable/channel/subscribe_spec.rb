# frozen_string_literal: true

module CableChannelSubscribeSpec
  class TestChannel < Rage::Cable::Channel
    def subscribed
      verifier.subscribed
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end

    def subscribed
      verifier.subscribed
    end
  end

  class TestChannel3 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end

    after_subscribe :verify_after_subscribe

    def subscribed
      verifier.subscribed
    end

    private def verify_after_subscribe
      verifier.after_subscribe
    end
  end

  class TestChannel4 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end

    after_subscribe do
      verifier.after_subscribe
    end

    def subscribed
      reject
    end
  end

  class TestChannel5 < Rage::Cable::Channel
    before_subscribe do
      reject
    end

    after_subscribe do
      verifier.after_subscribe
    end

    def subscribed
      verifier.subscribed
    end
  end

  class TestChannel6 < Rage::Cable::Channel
    after_subscribe :verify_after_subscribe

    def subscribed
      reject
    end

    private def verify_after_subscribe
      verifier.after_subscribe
    end
  end

  class TestChannel7 < Rage::Cable::Channel
    after_subscribe :verify_after_subscribe, unless: :subscription_rejected?

    def subscribed
      reject
    end

    private def verify_after_subscribe
      verifier.after_subscribe
    end
  end

  class TestChannel8 < Rage::Cable::Channel
    before_subscribe :verify_before_subscribe, if: :before_subscribe?
    after_subscribe :verify_after_subscribe, if: :after_subscribe?

    def subscribed
    end

    private

    def before_subscribe?
      true
    end

    def verify_before_subscribe
      verifier.before_subscribe
    end

    def after_subscribe?
      true
    end

    def verify_after_subscribe
      verifier.after_subscribe
    end
  end

  class TestChannel9 < Rage::Cable::Channel
    before_subscribe :verify_before_subscribe, if: :before_subscribe?
    after_subscribe :verify_after_subscribe, if: :after_subscribe?

    def subscribed
    end

    private

    def before_subscribe?
      false
    end

    def verify_before_subscribe
      verifier.before_subscribe
    end

    def after_subscribe?
      false
    end

    def verify_after_subscribe
      verifier.after_subscribe
    end
  end

  class TestChannel10 < Rage::Cable::Channel
  end

  class TestChannel11 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end
  end

  class TestChannel12 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end

    after_subscribe do
      verifier.after_subscribe
    end
  end

  class TestChannel13 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe_1
    end

    before_subscribe do
      verifier.before_subscribe_2
    end

    def subscribed
      verifier.subscribed
    end
  end

  class TestChannel14 < TestChannel13
    before_subscribe do
      verifier.before_subscribe_3
    end

    after_subscribe do
      verifier.after_subscribe
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  subject { klass.tap(&:__register_actions).new(nil, nil, nil).__run_action(:subscribed) }

  let(:verifier) { double }

  before do
    allow_any_instance_of(Rage::Cable::Channel).to receive(:verifier).and_return(verifier)
  end

  context "with the subscribed callback" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:subscribed).once
      subject
    end
  end

  context "with before_subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel2 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe).once
      expect(verifier).to receive(:subscribed).once
      subject
    end
  end

  context "with before_subscribe and after_subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel3 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe).once
      expect(verifier).to receive(:subscribed).once
      expect(verifier).to receive(:after_subscribe).once
      subject
    end
  end

  context "with subscription rejection" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel4 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe).once
      expect(verifier).to receive(:after_subscribe).once
      subject
    end
  end

  context "with rejection in before_subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel5 }

    it "correctly runs the subscribed callback" do
      expect(verifier).not_to receive(:subscribed)
      expect(verifier).not_to receive(:after_subscribe)
      subject
    end
  end

  context "with rejection and after_subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel6 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:after_subscribe).once
      subject
    end
  end

  context "with rejection and after_subscribe with the subscription_rejected? guard" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel7 }

    it "correctly runs the subscribed callback" do
      expect(verifier).not_to receive(:after_subscribe)
      subject
    end
  end

  context "with before/after subscribe and true conditionals" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel8 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe)
      expect(verifier).to receive(:after_subscribe)
      subject
    end
  end

  context "with before/after subscribe and false conditionals" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel9 }

    it "correctly runs the subscribed callback" do
      expect(verifier).not_to receive(:before_subscribe)
      expect(verifier).not_to receive(:after_subscribe)
      subject
    end
  end

  context "with the default callback" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel10 }

    it "correctly runs the subscribed callback" do
      expect { subject }.not_to raise_error
    end
  end

  context "with the default callback and before_subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel11 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe)
      subject
    end
  end

  context "with the default callback and before/after subscribe" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel12 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe)
      expect(verifier).to receive(:after_subscribe)
      subject
    end
  end

  context "with multiple before_subscribe callbacks" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel13 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe_1)
      expect(verifier).to receive(:before_subscribe_2)
      expect(verifier).to receive(:subscribed)
      subject
    end
  end

  context "with inheritance" do
    let(:klass) { CableChannelSubscribeSpec::TestChannel14 }

    it "correctly runs the subscribed callback" do
      expect(verifier).to receive(:before_subscribe_1)
      expect(verifier).to receive(:before_subscribe_2)
      expect(verifier).to receive(:before_subscribe_3)
      expect(verifier).to receive(:subscribed)
      expect(verifier).to receive(:after_subscribe)
      subject
    end
  end
end

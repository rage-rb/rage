# frozen_string_literal: true

module CableChannelActionsSpec
  class TestChannel < Rage::Cable::Channel
  end

  class TestChannel1 < Rage::Cable::Channel
    def receive
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    def subscribed
    end

    def receive
    end

    def unsubscribed
    end
  end

  class TestChannel3 < TestChannel2
    def connect
    end
  end

  class TestChannel4 < Rage::Cable::Channel
    protected def protected_action
    end

    private def private_action
    end
  end

  class TestChannel5 < Rage::Cable::Channel
    before_subscribe do
      verifier.before_subscribe
    end

    after_subscribe do
      verifier.after_subscribe
    end

    def receive
      verifier.receive
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  let(:klass_instance) { klass.tap(&:__register_actions).new(nil, nil, nil) }

  context "with default actions" do
    let(:klass) { CableChannelActionsSpec::TestChannel }

    it "correctly registers actions" do
      expect(klass.__register_actions).to be_empty
    end

    describe "#__has_action?" do
      it "correctly fetches available actions" do
        expect(klass_instance.__has_action?(:subscribed)).to be(false)
        expect(klass_instance.__has_action?(:unsubscribed)).to be(false)
      end
    end
  end

  context "with a custom action" do
    let(:klass) { CableChannelActionsSpec::TestChannel1 }

    it "correctly registers actions" do
      expect(klass.__register_actions).to eq(%i(receive))
    end

    describe "#__has_action?" do
      it "correctly fetches available actions" do
        expect(klass_instance.__has_action?(:receive)).to be(true)
      end
    end
  end

  context "with a custom action and subscription callbacks" do
    let(:klass) { CableChannelActionsSpec::TestChannel2 }

    it "correctly registers actions" do
      expect(klass.__register_actions).to eq(%i(receive))
    end

    describe "#__has_action?" do
      it "correctly fetches available actions" do
        expect(klass_instance.__has_action?(:receive)).to be(true)
      end
    end
  end

  context "with inheritance" do
    let(:klass) { CableChannelActionsSpec::TestChannel3 }

    it "correctly registers actions" do
      expect(klass.__register_actions).to match_array(%i(receive connect))
    end

    describe "#__has_action?" do
      it "correctly fetches available actions" do
        expect(klass_instance.__has_action?(:receive)).to be(true)
        expect(klass_instance.__has_action?(:connect)).to be(true)
      end
    end
  end

  context "with protected and private methods" do
    let(:klass) { CableChannelActionsSpec::TestChannel4 }

    it "correctly registers actions" do
      expect(klass.__register_actions).to be_empty
    end
  end

  context "with before/after subscribe and custom action" do
    let(:klass) { CableChannelActionsSpec::TestChannel5 }

    it "correctly registers actions" do
      expect(klass.__register_actions).to eq([:receive])
    end

    describe "#__has_action?" do
      it "correctly fetches available actions" do
        expect(klass_instance.__has_action?(:receive)).to be(true)
      end
    end

    describe "#__run_action" do
      let(:verifier) { double }

      before do
        allow_any_instance_of(Rage::Cable::Channel).to receive(:verifier).and_return(verifier)
        klass.__register_actions
      end

      it "doesn't call before/after subscribe when calling custom action" do
        expect(verifier).to receive(:receive).once
        expect(verifier).not_to receive(:before_subscribe)
        expect(verifier).not_to receive(:after_subscribe)

        klass_instance.__run_action(:receive)
      end
    end
  end
end

# frozen_string_literal: true

module CableChannelRescueFromSpec
  class TestChannel < Rage::Cable::Channel
    rescue_from ZeroDivisionError do
      verifier.rescue_from
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    rescue_from ZeroDivisionError do
      verifier.rescue_from
    end

    def subscribed
      raise NameError
    end
  end

  class TestChannel3 < Rage::Cable::Channel
    rescue_from NameError do
      verifier.rescue_from_name_error
    end

    rescue_from ZeroDivisionError do
      verifier.rescue_from_zero_error
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel4 < TestChannel3
    def subscribed
      raise NameError
    end
  end

  class TestChannel5 < Rage::Cable::Channel
    rescue_from NameError, ZeroDivisionError do
      verifier.rescue_from
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel6 < Rage::Cable::Channel
    rescue_from ZeroDivisionError, with: :process_exception

    def subscribed
      raise ZeroDivisionError
    end

    private def process_exception
      verifier.rescue_from
    end
  end

  class TestChannel7 < Rage::Cable::Channel
    rescue_from StandardError do
      verifier.rescue_from
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel8 < Rage::Cable::Channel
    rescue_from ZeroDivisionError do
      verifier.rescue_from
    end

    def receive
      raise ZeroDivisionError
    end
  end

  class TestChannel9 < Rage::Cable::Channel
    rescue_from ZeroDivisionError do
      verifier.rescue_from_zero_error
    end

    rescue_from StandardError do
      verifier.rescue_from_standard_error
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel10 < Rage::Cable::Channel
    rescue_from ZeroDivisionError do
      verifier.rescue_from
    end

    before_subscribe do
      raise ZeroDivisionError
    end
  end

  class TestChannel11 < Rage::Cable::Channel
    rescue_from ZeroDivisionError do |exception|
      verifier.rescue_from(exception)
    end

    def subscribed
      raise ZeroDivisionError
    end
  end

  class TestChannel12 < Rage::Cable::Channel
    rescue_from ZeroDivisionError, with: :process_exception

    def subscribed
      raise ZeroDivisionError
    end

    private def process_exception(exception)
      verifier.rescue_from(exception)
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  subject { klass.tap(&:__register_actions).new(nil, nil, nil).__run_action(:subscribed) }

  let(:verifier) { double }

  before do
    allow_any_instance_of(Rage::Cable::Channel).to receive(:verifier).and_return(verifier)
  end

  context "with rescue_from" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with rescue_from and unexpected error" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel2 }

    it "correctly processes exceptions" do
      expect(verifier).not_to receive(:rescue_from_zero_error)
      expect { subject }.to raise_error(NameError)
    end
  end

  context "with multiple rescue_from" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel3 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from_zero_error).once
      subject
    end
  end

  context "with inheritance" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel4 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from_name_error).once
      subject
    end
  end

  context "with rescue_from with multiple error classes" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel5 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with a method handler" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel6 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with StandardError" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel7 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with custom action" do
    subject { klass.tap(&:__register_actions).new(nil, nil, nil).__run_action(:receive) }

    let(:klass) { CableChannelRescueFromSpec::TestChannel8 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with multiple rescue_from matching the error" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel9 }

    it "matches handlers from bottom to top" do
      expect(verifier).to receive(:rescue_from_standard_error).once
      subject
    end
  end

  context "with error in before_subscribe" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel10 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).once
      subject
    end
  end

  context "with block handler accepting the exception" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel11 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).with(ZeroDivisionError).once
      subject
    end
  end

  context "with method handler accepting the exception" do
    let(:klass) { CableChannelRescueFromSpec::TestChannel12 }

    it "correctly processes exceptions" do
      expect(verifier).to receive(:rescue_from).with(ZeroDivisionError).once
      subject
    end
  end
end

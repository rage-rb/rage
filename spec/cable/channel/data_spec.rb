# frozen_string_literal: true

module CableChannelDataSpec
  class TestChannel < Rage::Cable::Channel
    def receive
      verifier.receive
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    def receive(data)
      verifier.receive(data)
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  subject { klass.tap(&:__register_actions).new(nil, nil, nil) }

  let(:verifier) { double }

  before do
    allow_any_instance_of(Rage::Cable::Channel).to receive(:verifier).and_return(verifier)
  end

  context "expecting no data" do
    let(:klass) { CableChannelDataSpec::TestChannel }

    it "correctly processes remote method calls with no data" do
      expect(verifier).to receive(:receive).once
      subject.__run_action(:receive)
    end

    it "correctly processes remote method calls with data" do
      expect(verifier).to receive(:receive).once
      subject.__run_action(:receive, :test_data)
    end
  end

  context "expecting data" do
    let(:klass) { CableChannelDataSpec::TestChannel2 }

    it "correctly processes remote method calls" do
      expect(verifier).to receive(:receive).with(:test_data).once
      subject.__run_action(:receive, :test_data)
    end

    it "doesn't cache data" do
      expect(verifier).to receive(:receive).with(:test_data).once
      expect(verifier).to receive(:receive).with(:another_test_data).once

      subject.__run_action(:receive, :test_data)
      subject.__run_action(:receive, :another_test_data)
    end
  end
end

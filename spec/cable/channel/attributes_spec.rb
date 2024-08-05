# frozen_string_literal: true

RSpec.describe Rage::Cable::Channel do
  describe "#params" do
    subject { described_class.new(nil, :test_params, nil) }

    it "correctly returns params" do
      expect(subject.params).to eq(:test_params)
    end
  end

  describe "#subscription_rejected?" do
    subject { described_class.new(nil, nil, nil) }

    it "does not reject by default" do
      expect(subject).not_to be_subscription_rejected
    end

    it "correctly rejects subscription" do
      subject.reject
      expect(subject).to be_subscription_rejected
    end
  end
end

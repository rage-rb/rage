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

  describe "#env" do
    subject { described_class.new(connection, nil, nil) }

    let(:connection) { double(env: :test_env) }

    it "returns connection env" do
      expect(subject.env).to eq(:test_env)
    end
  end
end

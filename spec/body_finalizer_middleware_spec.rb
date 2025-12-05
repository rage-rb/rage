# frozen_string_literal: true

RSpec.describe Rage::BodyFinalizer do
  subject { described_class.new(app).call(env) }

  let(:env) { {} }
  let(:body) { double }
  let(:response) { [200, {}, body] }
  let(:app) { double(call: response) }

  it "closes the body" do
    expect(body).to receive(:close)
    subject
  end

  it "returns the response" do
    allow(body).to receive(:close)
    expect(subject).to eq(response)
  end
end

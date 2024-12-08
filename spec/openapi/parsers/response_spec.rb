# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Response do
  subject { described_class.parse(tag, namespace:) }

  let(:tag) { "test_tag" }
  let(:namespace) { double }

  before do
    described_class::AVAILABLE_PARSERS.each do |parser_class|
      parser = double
      allow(parser_class).to receive(:new).with(namespace:).and_return(parser)
      allow(parser).to receive(:known_definition?).and_return(false)
    end
  end

  context "with no matching parsers" do
    it { is_expected.to be_nil }
  end

  context "with a matching parser" do
    let(:parser) { double }

    before do
      allow(Rage::OpenAPI::Parsers::Ext::ActiveRecord).to receive(:new).with(namespace:).and_return(parser)
      allow(parser).to receive(:known_definition?).and_return(true)
    end

    it do
      expect(parser).to receive(:parse).and_return("test_parse_result")
      expect(subject).to eq("test_parse_result")
    end
  end
end

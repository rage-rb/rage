# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::SharedReference do
  subject { described_class.new.parse(ref) }

  let(:config) do
    YAML.safe_load <<~YAML
      components:
        schemas:
          User:
            type: object
          Error:
            type: object
        parameters:
          offsetParam:
            name: offset
        responses:
          404NotFound:
            description: The specified resource was not found.
          ImageResponse:
            description: An image.
    YAML
  end

  before do
    allow(Rage::OpenAPI).to receive(:__shared_components).and_return(config)
  end

  context "with schema" do
    context "with User" do
      let(:ref) { "#/components/schemas/User" }
      it { is_expected.to eq({ "$ref" => ref }) }
    end

    context "with Error" do
      let(:ref) { "#/components/schemas/Error" }
      it { is_expected.to eq({ "$ref" => ref }) }
    end

    context "with invalid key" do
      let(:ref) { "#/components/schemas/Ok" }
      it { is_expected.to be_nil }
    end
  end

  context "with parameters" do
    context "with offsetParam" do
      let(:ref) { "#/components/parameters/offsetParam" }
      it { is_expected.to eq({ "$ref" => ref }) }
    end

    context "with invalid key" do
      let(:ref) { "#/components/parameters/pageParam" }
      it { is_expected.to be_nil }
    end
  end

  context "with responses" do
    context "with 404NotFound" do
      let(:ref) { "#/components/responses/404NotFound" }
      it { is_expected.to eq({ "$ref" => ref }) }
    end

    context "with ImageResponse" do
      let(:ref) { "#/components/responses/ImageResponse" }
      it { is_expected.to eq({ "$ref" => ref }) }
    end

    context "with invalid key" do
      let(:ref) { "#/components/responses/GenericError" }
      it { is_expected.to be_nil }
    end
  end

  context "with invalid component" do
    let(:ref) { "#/components/model/User" }
    it { is_expected.to be_nil }
  end

  context "with no components" do
    let(:config) { {} }
    let(:ref) { "#/components/schemas/User" }

    it { is_expected.to be_nil }
  end
end

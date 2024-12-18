# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::ActiveRecord do
  include_context "mocked_classes"

  subject { described_class.new.parse(arg) }

  let_class("User")
  let(:arg) { "User" }

  let(:attributes) { {} }
  let(:inheritance_column) { nil }
  let(:enums) { [] }

  before do
    klass = Object.const_get("User")

    allow(klass).to receive(:attribute_types).and_return(attributes)
    allow(klass).to receive(:inheritance_column).and_return(inheritance_column)
    allow(klass).to receive(:defined_enums).and_return(enums)
  end

  context "with no attributes" do
    it do
      is_expected.to eq({ "type" => "object" })
    end

    context "with collection" do
      let(:arg) { "[User]" }

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object" } })
      end
    end
  end

  context "with attributes" do
    let(:attributes) { { age: double(type: :integer), admin: double(type: :boolean), comments: double(type: :json) } }

    it do
      is_expected.to eq({ "type" => "object", "properties" => { :age => { "type" => "integer" }, :admin => { "type" => "boolean" }, :comments => { "type" => "object" } } })
    end

    context "with collection" do
      let(:arg) { "[User]" }

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { :age => { "type" => "integer" }, :admin => { "type" => "boolean" }, :comments => { "type" => "object" } } } })
      end
    end
  end

  context "with inheritance column" do
    let(:attributes) { { age: double(type: :integer), type: double(type: :string) } }
    let(:inheritance_column) { :type }

    it do
      is_expected.to eq({ "type" => "object", "properties" => { :age => { "type" => "integer" } } })
    end
  end

  context "with enum" do
    let(:attributes) { { email: double(type: :string) } }
    let(:enums) { { status: double(keys: %i(active inactive)) } }

    it do
      is_expected.to eq({ "type" => "object", "properties" => { :email => { "type" => "string" }, :status => { "type" => "string", "enum" => [:active, :inactive] } } })
    end
  end

  context "with unknown type" do
    let(:attributes) { { uuid: double(type: :uuid) } }

    it do
      is_expected.to eq({ "type" => "object", "properties" => { :uuid => { "type" => "string" } } })
    end
  end
end

# frozen_string_literal: true

require "prism"
require "blueprinter"
require "rage/openapi/parsers/ext/blueprinter"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource, **parse_options) }

  let(:options) { {} }
  let(:parse_options) { {} }
  let(:resource) { "UserBlueprint" }

  context "with a single field" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
      RUBY
    end

    it do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      })
    end
  end

  context "with multiple fields" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        field :email
        field :age
      RUBY
    end

    it do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "email" => { "type" => "string" },
          "age" => { "type" => "string" }
        }
      })
    end
  end

  context "with an identifier" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        identifier :id
        field :name
      RUBY
    end

    it do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "id" => { "type" => "string" },
          "name" => { "type" => "string" }
        }
      })
    end
  end

  context "with an association" do
    let_class("AddressBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :street
        field :city
      RUBY
    end

    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        association :address, blueprint: AddressBlueprint
      RUBY
    end

    it do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "address" => {
            "type" => "object",
            "properties" => {
              "street" => { "type" => "string" },
              "city" => { "type" => "string" }
            }
          }
        }
      })
    end
  end

  context "with an association without blueprint" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        association :metadata
      RUBY
    end

    it do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "metadata" => { "type" => "object" }
        }
      })
    end
  end

  context "with a default view" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        field :email
        view :extended do
          field :phone
        end
      RUBY
    end

    it "returns only default fields" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "email" => { "type" => "string" }
        }
      })
    end
  end

  context "with an extended view" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        field :email
        view :extended do
          field :phone
          field :age
        end
      RUBY
    end

    let(:parse_options) { { view: :extended } }

    it "returns default fields plus extended fields" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "email" => { "type" => "string" },
          "phone" => { "type" => "string" },
          "age" => { "type" => "string" }
        }
      })
    end
  end

  context "with a collection" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
        field :email
      RUBY
    end

    let(:resource) { "[UserBlueprint]" }

    it "wraps schema in array" do
      is_expected.to eq({
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        }
      })
    end
  end

  context "with known_definition?" do
    let_class("UserBlueprint", parent: Blueprinter::Base) do
      <<~'RUBY'
        field :name
      RUBY
    end

    it "returns true for a valid blueprint" do
      expect(described_class.new.known_definition?("UserBlueprint")).to be(true)
    end

    it "returns false for an unknown class" do
      expect(described_class.new.known_definition?("UnknownClass")).to be(false)
    end
  end
end

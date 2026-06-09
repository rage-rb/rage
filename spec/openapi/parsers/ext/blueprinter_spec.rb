# frozen_string_literal: true

require "blueprinter"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_blueprinter_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }

  describe "single object" do
    let(:resource) { "UserBlueprint" }

    context "with an empty blueprint" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object" })
      end
    end

    context "with basic fields" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name, :email, :age
        RUBY
      end
      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "age" => { "type" => "string" },
            "email" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" }
          }
        })
      end
    end

    context "when fields are declared with strings" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields "id", "name", "email"
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with identifier" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" }
          }
        })
      end
    end

    context "with a single field" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          field :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with field name alias" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          field :email, name: :login
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "login" => { "type" => "string" }
          }
        })
      end
    end

    context "when field alias is declared with string values" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          field "email", name: "login"
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "login" => { "type" => "string" }
          }
        })
      end
    end

    context "with a block field" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with a block field declared with string values" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with all declaration types combined" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :id, :name, :age
          field :email, name: :login
          fields :first_name, :last_name
          field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "age" => { "type" => "string" },
            "login" => { "type" => "string" },
            "first_name" => { "type" => "string" },
            "last_name" => { "type" => "string" },
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with all declaration types combined with string values" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields "id", "name", "age"
          field "email", name: "login"
          fields "first_name", "last_name"
          field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "age" => { "type" => "string" },
            "login" => { "type" => "string" },
            "first_name" => { "type" => "string" },
            "last_name" => { "type" => "string" },
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with all declaration types combined with string and symbol vales" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :id, "name", :age
          field :email, name: "login"
          fields "first_name", :last_name
          field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "age" => { "type" => "string" },
            "login" => { "type" => "string" },
            "first_name" => { "type" => "string" },
            "last_name" => { "type" => "string" },
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "ensures identifier appears first in properties regardless of definition order" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name, :email
          identifier :uuid
        RUBY
      end
      it do
        expect(subject["properties"].keys.first).to eq("uuid")
      end
    end

    context "with inheritance from another blueprint" do
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :email, :age
        RUBY
      end

      it "merges parent schema into child schema" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" },
            "age" => { "type" => "string" }
          }
        })
      end
    end

    context "when superclass is Base (should not merge)" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      it "does not attempt to parse superclass" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" }
          }
        })
      end
    end

    context "when child blueprint overrides a parent field" do
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :name, :email
        RUBY
      end

      it "child fields take precedence" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with multiple levels of inheritance" do
      let_class("GrandparentBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
        <<~'RUBY'
          fields :age
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" },
            "age" => { "type" => "string" }
          }
        })
      end
    end

    context "with identifier in parent blueprint" do
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          identifier :id
          fields :email
        RUBY
      end

      it "inherits identifier from parent" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
        expect(subject["properties"].keys.first).to eq("uuid")
        expect(subject["properties"].keys[1]).to eq("id")
      end
    end
  end

  describe "collection" do
    let(:resource) { "Array<UserBlueprint>" }

    context "with basic fields" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name, :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with identifier" do
      let(:resource) { "[UserBlueprint]" }
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name, :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "uuid" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with inherited fields" do
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with multiple levels of inheritance" do
      let_class("GrandparentBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end
      let_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end
      let_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
        <<~'RUBY'
          fields :age
        RUBY
      end
      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" },
              "age" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with identifier in parent blueprint" do
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end
      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          identifier :id
          fields :email
        RUBY
      end
      it "inherits identifier from parent" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "uuid" => { "type" => "string" },
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
        expect(subject["items"]["properties"].keys.first).to eq("uuid")
        expect(subject["items"]["properties"].keys[1]).to eq("id")
      end
    end
  end
end

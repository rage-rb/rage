# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }

  describe "single object" do
    let(:resource) { "UserBlueprint" }

    context "with an empty blueprint" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object" })
      end
    end

    context "with basic fields" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :id, :name, :email, :age
          end
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

    context "when fields are declared with strings" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields "id", "name", "email"
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field :email
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field :email, name: :login
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field "email", name: "login"
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :id, :name, :age
            field :email, name: :login
            fields :first_name, :last_name
            field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields "id", "name", "age"
            field "email", name: "login"
            fields "first_name", "last_name"
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :id, "name", :age
            field :email, name: "login"
            fields "first_name", :last_name
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :name, :email
            identifier :uuid
          end
        RUBY
      end
      it do
        expect(subject["properties"].keys.first).to eq("uuid")
      end
    end
  end

  describe "collection" do
    let(:resource) { "Array<UserBlueprint>" }

    context "with basic fields" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :id, :name, :email
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name, :email
          end
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
  end
end

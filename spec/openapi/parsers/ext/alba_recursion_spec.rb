# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Alba do
  include_context "mocked_classes"

  subject { described_class.new.parse(resource) }

  let(:resource) { "UserResource" }

  context "with direct circular associations (UserResource ↔ PostResource)" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        has_many :posts, resource: "PostResource"
      RUBY
    end

    let_class("PostResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :title
        has_one :author, resource: "UserResource"
      RUBY
    end

    it "does not raise SystemStackError" do
      expect { subject }.not_to raise_error
    end

    it "stops recursion with a fallback object schema" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "id" => { "type" => "string" },
          "name" => { "type" => "string" },
          "posts" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "title" => { "type" => "string" },
                "author" => { "type" => "object" }
              }
            }
          }
        }
      })
    end
  end

  context "with a self-referencing resource" do
    let(:resource) { "CategoryResource" }

    let_class("CategoryResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        has_many :subcategories, resource: "CategoryResource"
      RUBY
    end

    it "does not raise SystemStackError" do
      expect { subject }.not_to raise_error
    end

    it "stops recursion on the self-reference" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "id" => { "type" => "string" },
          "name" => { "type" => "string" },
          "subcategories" => {
            "type" => "array",
            "items" => { "type" => "object" }
          }
        }
      })
    end
  end

  context "with transitive circular associations (A → B → C → A)" do
    let(:resource) { "AResource" }

    let_class("AResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :a_id
        has_one :b, resource: "BResource"
      RUBY
    end

    let_class("BResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :b_id
        has_one :c, resource: "CResource"
      RUBY
    end

    let_class("CResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :c_id
        has_one :a, resource: "AResource"
      RUBY
    end

    it "does not raise SystemStackError" do
      expect { subject }.not_to raise_error
    end

    it "stops recursion at the cycle point" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "a_id" => { "type" => "string" },
          "b" => {
            "type" => "object",
            "properties" => {
              "b_id" => { "type" => "string" },
              "c" => {
                "type" => "object",
                "properties" => {
                  "c_id" => { "type" => "string" },
                  "a" => { "type" => "object" }
                }
              }
            }
          }
        }
      })
    end
  end
end

# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Alba do
  include_context "mocked_classes"

  subject { described_class.new.parse(resource) }

  let(:resource) { "UserResource" }

  context "with an unresolvable association" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id
        has_many :posts, resource: "NonExistentResource"
        has_one :profile, resource: "MissingProfileResource"
      RUBY
    end

    it "uses a default fallback schema" do
      is_expected.to eq({
        "type" => "object",
        "properties" => {
          "id" => { "type" => "string" },
          "posts" => { "type" => "array", "items" => { "type" => "object" } },
          "profile" => { "type" => "object" }
        }
      })
    end

    it "logs a warning" do
      expect(Rage::OpenAPI).to receive(:__log_warn).with("could not resolve resource: NonExistentResource")
      expect(Rage::OpenAPI).to receive(:__log_warn).with("could not resolve resource: MissingProfileResource")
      subject
    end
  end
end

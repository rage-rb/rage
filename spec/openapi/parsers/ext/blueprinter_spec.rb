# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }
  let(:resource) { "UserBlueprint" }

  context "with an empty blueprint" do
    let_class("UserBlueprint") do
      <<~'RUBY'
        class UserBlueprint < Blueprinter::Base
          fields :id, :name, :email, :age
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object" })
    end
  end
end

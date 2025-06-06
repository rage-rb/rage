# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@description" do
    context "with one-line description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @description Returns the list of all internal and external users.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "Returns the list of all internal and external users.", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multi-line description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @description Returns the list of users.
          #   Pass `with_deleted` to include deleted records.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "Returns the list of users. Pass `with_deleted` to include deleted records.", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with summary" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of users.
          # @description The list includes both internal and external users.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of users.", "description" => "The list includes both internal and external users.", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end
  end
end

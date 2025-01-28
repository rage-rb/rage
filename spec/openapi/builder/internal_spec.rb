# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@internal" do
    context "with an internal comment" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @internal this is an internal comment
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with a multi-line internal comment" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @internal this
          #   is
          #   an
          #   internal
          #   comment
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with another tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @internal this is an internal comment
          # @deprecated
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with an empty comment" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          # @deprecated
          #
          # @internal this is an internal comment
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "does not log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end
  end
end

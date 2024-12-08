# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@deprecated" do
    context "with a deprecated method" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
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

    context "with multiple methods" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
          def index
          end

          def create
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index",
          "POST /users" => "UsersController#create"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with a deprecated controller" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated

          def index
          end

          def create
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index",
          "POST /users" => "UsersController#create"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with inherited deprecated method" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
          def index
          end
        RUBY
      end

      let_class("UsersController", parent: mocked_classes.BaseController)

      let(:routes) { { "GET /users" => "UsersController#index" } }

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with overriden deprecated method" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
          def index
          end
        RUBY
      end

      let_class("UsersController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let(:routes) { { "GET /users" => "UsersController#index" } }

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with deprecated parent" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
        RUBY
      end

      let_class("UsersController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          def index
          end

          def create
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index",
          "POST /users" => "UsersController#create"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with duplicate tags" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
        RUBY
      end

      let_class("UsersController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # @deprecated
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/duplicate `@deprecated` tag detected/)
        subject
      end
    end

    context "with internal comments" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated Use Members API instead
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multi-line internal comments" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated Use
          #   Members
          #   API
          #   instead
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multi-line internal comments and another tags" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated Use
          #   Members
          #   API
          #   instead
          # @description Test
          #   API
          #   Description
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "Test API Description", "deprecated" => true, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with incorrect tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecatedd
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized `@deprecatedd` tag detected/)
        subject
      end
    end

    context "with deprecated class in a separate inheritance chain" do
      let_class("BaseController", parent: RageController::API)

      let_class("Api::V1::BaseController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # @deprecated
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes["Api::V1::BaseController"]) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let_class("Api::V2::BaseController", parent: mocked_classes.BaseController)

      let_class("Api::V2::UsersController", parent: mocked_classes["Api::V2::BaseController"]) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /api/v1/users" => "Api::V1::UsersController#index",
          "GET /api/v2/users" => "Api::V2::UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v1/Users" }, { "name" => "v2/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => true, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } }, "/api/v2/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end
  end
end

# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@params" do
    let(:shared_components) do
      YAML.safe_load(
        <<~YAML
          components:
            parameters:
              perPageParam:
                in: query
                name: per_page
                required: false
                schema:
                  type: integer
                  minimum: 1
                  maximum: 500
                  default: 100
                description: The number of records to return.
        YAML
      )
    end

    context "with typed param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Boolean} The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "The status of the user records", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with optional typed param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active? {Boolean} The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => false, "description" => "The status of the user records", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with typed param" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Boolean}
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with invalid typed param" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Boolean}IsActive
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "{Boolean}IsActive", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "doesn't log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end

    context "with optional typed param" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active? {Boolean}
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => false, "description" => "", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "The status of the user records", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with param with one-word description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active IsActive
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "IsActive", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "doesn't log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end

    context "with optional param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active? The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => false, "description" => "The status of the user records", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with param" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with optional param" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active?
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => false, "description" => "", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with type guessing" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param account_id
          # @param archived_at
          # @param email
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "account_id", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "integer" } }, { "name" => "archived_at", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "string", "format" => "date-time" } }, { "name" => "email", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with invalid type with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Symbol} The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "The status of the user records", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized type Symbol/)
        subject
      end
    end

    context "with invalid type with no description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Symbol}
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "string" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized type Symbol/)
        subject
      end
    end

    context "with shared reference" do
      before do
        allow(Rage::OpenAPI).to receive(:__shared_components).and_return(shared_components)
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param #/components/parameters/perPageParam
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "parameters" => { "perPageParam" => { "in" => "query", "name" => "per_page", "required" => false, "schema" => { "type" => "integer", "minimum" => 1, "maximum" => 500, "default" => 100 }, "description" => "The number of records to return." } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "$ref" => "#/components/parameters/perPageParam" }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with invalid shared reference" do
      before do
        allow(Rage::OpenAPI).to receive(:__shared_components).and_return(shared_components)
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param #/components/parameters/pageParam
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/invalid shared reference detected/)
        subject
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "parameters" => { "perPageParam" => { "in" => "query", "name" => "per_page", "required" => false, "schema" => { "type" => "integer", "minimum" => 1, "maximum" => 500, "default" => 100 }, "description" => "The number of records to return." } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multiple params" do
      before do
        allow(Rage::OpenAPI).to receive(:__shared_components).and_return(shared_components)
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Boolean}
          # @param page? {Integer}
          # @param #/components/parameters/perPageParam
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "parameters" => { "perPageParam" => { "in" => "query", "name" => "per_page", "required" => false, "schema" => { "type" => "integer", "minimum" => 1, "maximum" => 500, "default" => 100 }, "description" => "The number of records to return." } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "", "schema" => { "type" => "boolean" } }, { "name" => "page", "in" => "query", "required" => false, "description" => "", "schema" => { "type" => "integer" } }, { "$ref" => "#/components/parameters/perPageParam" }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with typed URL param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param account {Integer} ID of the account the users are attached to
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /:account/users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/{account}/users" => { "parameters" => [{ "in" => "path", "name" => "account", "required" => true, "description" => "ID of the account the users are attached to", "schema" => { "type" => "integer" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with typed URL param with no description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param account {Integer}
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /:account/users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/{account}/users" => { "parameters" => [{ "in" => "path", "name" => "account", "required" => true, "description" => "", "schema" => { "type" => "integer" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with URL param with description" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param account ID of the account the users are attached to
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /:account/users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/{account}/users" => { "parameters" => [{ "in" => "path", "name" => "account", "required" => true, "description" => "ID of the account the users are attached to", "schema" => { "type" => "string" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with regular and URL params" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param account {Integer} ID of the account the users are attached to
          # @param is_active {Boolean} The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /:account/users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/{account}/users" => { "parameters" => [{ "in" => "path", "name" => "account", "required" => true, "description" => "ID of the account the users are attached to", "schema" => { "type" => "integer" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "The status of the user records", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with regular and implicit URL params" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @param is_active {Boolean} The status of the user records
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /:account/users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/{account}/users" => { "parameters" => [{ "in" => "path", "name" => "account", "required" => true, "description" => "", "schema" => { "type" => "string" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "parameters" => [{ "name" => "is_active", "in" => "query", "required" => true, "description" => "The status of the user records", "schema" => { "type" => "boolean" } }], "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end
  end
end

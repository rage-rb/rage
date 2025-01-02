# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@response" do
    context "with a data response" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response { id: Integer, full_name: String }
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } } } } } })
      end
    end

    context "with a status code response" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response 204
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "204" => { "description" => "" } } } } } })
      end
    end

    context "with both data and status response" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response 202 { id: Integer, full_name: String }
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "202" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } } } } } })
      end
    end

    context "with multiple responses" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response { id: Integer, full_name: String }
          # @response 500 { session_id: String }
          # @response 404
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } }, "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } } }, "404" => { "description" => "" } } } } } })
      end
    end

    context "with collection responses" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response [{ id: Integer, full_name: String }]
          # @response 500 { session_id: String }
          # @response 404
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } }, "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } } }, "404" => { "description" => "" } } } } } })
      end
    end

    context "with serializer responses" do
      before do
        allow_any_instance_of(Rage::OpenAPI::Parsers::Ext::Alba).to receive(:known_definition?).and_call_original
        allow_any_instance_of(Rage::OpenAPI::Parsers::Ext::Alba).to receive(:known_definition?).with("UserResource").and_return(true)
      end

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :full_name, :email
        RUBY
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response UserResource
          # @response 500 { session_id: String }
          # @response 404
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "full_name" => { "type" => "string" }, "email" => { "type" => "string" } } } } } }, "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } } }, "404" => { "description" => "" } } } } } })
      end
    end

    context "with serializer collection" do
      before do
        allow_any_instance_of(Rage::OpenAPI::Parsers::Ext::Alba).to receive(:known_definition?).and_call_original
        allow_any_instance_of(Rage::OpenAPI::Parsers::Ext::Alba).to receive(:known_definition?).with("[UserResource]").and_return(true)
      end

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :full_name, :email
        RUBY
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response 202 [UserResource]
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "202" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "full_name" => { "type" => "string" }, "email" => { "type" => "string" } } } } } } } } } } } })
      end
    end

    context "with shared reference" do
      before do
        allow(Rage::OpenAPI).to receive(:__shared_components).and_return(YAML.safe_load(<<~YAML
          components:
            schemas:
              User:
                type: object
                properties:
                  id:
                    type: integer
                    format: int64
                  name:
                    type: string
            responses:
              404NotFound:
                description: The specified resource was not found.
        YAML
                                                                                       ))
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response #/components/schemas/User
          # @response 404 #/components/responses/404NotFound
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "schemas" => { "User" => { "type" => "object", "properties" => { "id" => { "type" => "integer", "format" => "int64" }, "name" => { "type" => "string" } } } }, "responses" => { "404NotFound" => { "description" => "The specified resource was not found." } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/User" } } } }, "404" => { "$ref" => "#/components/responses/404NotFound" } } } } } })
      end
    end

    context "with invalid serializer" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response UnknownResource
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

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized `@response` tag detected/)
        subject
      end
    end

    context "with duplicate tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @response 200 { id: Integer, full_name: String }
          # @response 404
          # @response { uuid: String }
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } }, "404" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/duplicate `@response` tag detected at .+:4/)
        subject
      end
    end

    context "with global tag" do
      let_class("ApplicationController", parent: RageController::API) do
        <<~'RUBY'
          # @response 500 { status: String }
        RUBY
      end

      let_class("Api::V1::BaseController", parent: mocked_classes.ApplicationController) do
        <<~'RUBY'
          # @response 500 { error: INTERNAL_SERVER_ERROR, session_id: String }
          # @response 404 { error: NOT_FOUND, session_id: String }
        RUBY
      end

      let_class("UsersController", parent: mocked_classes["Api::V1::BaseController"]) do
        <<~'RUBY'
          # @response [{ id: Integer, full_name: String }]
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "error" => { "type" => "string", "enum" => ["INTERNAL_SERVER_ERROR"] }, "session_id" => { "type" => "string" } } } } } }, "404" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "error" => { "type" => "string", "enum" => ["NOT_FOUND"] }, "session_id" => { "type" => "string" } } } } } }, "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } } } } } } })
      end

      context "with empty parent nodes" do
        let_class("ApplicationController", parent: RageController::API) do
          <<~'RUBY'
            # @response 500 { status: String }
          RUBY
        end

        let_class("Api::V1::BaseController", parent: mocked_classes.ApplicationController)

        let_class("UsersController", parent: mocked_classes["Api::V1::BaseController"]) do
          <<~'RUBY'
            # @response [{ id: Integer, full_name: String }]
            def index
            end
          RUBY
        end

        let(:routes) do
          { "GET /users" => "UsersController#index" }
        end

        it "returns correct schema" do
          expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "status" => { "type" => "string" } } } } } }, "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } } } } } } })
        end
      end

      context "with override in method node" do
        let_class("ApplicationController", parent: RageController::API) do
          <<~'RUBY'
            # @response 500 { status: String }
          RUBY
        end

        let_class("UsersController", parent: mocked_classes.ApplicationController) do
          <<~'RUBY'
            # @response [{ id: Integer, full_name: String }]
            # @response 500 { error: INTERNAL_SERVER_ERROR, session_id: String }
            def index
            end
          RUBY
        end

        let(:routes) do
          { "GET /users" => "UsersController#index" }
        end

        it "returns correct schema" do
          expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "500" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "error" => { "type" => "string", "enum" => ["INTERNAL_SERVER_ERROR"] }, "session_id" => { "type" => "string" } } } } } }, "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "full_name" => { "type" => "string" } } } } } } } } } } } })
        end
      end
    end
  end
end

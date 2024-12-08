# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@request" do
    context "with a data request" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @request { email: String, password: String }
          def create
          end
        RUBY
      end

      let(:routes) do
        { "POST /users" => "UsersController#create" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } }, "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "email" => { "type" => "string" }, "password" => { "type" => "string" } } } } } } } } } })
      end
    end

    context "with shared requestBody reference" do
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
            requestBodies:
              UserBody:
                description: A JSON object containing user information
                required: true
                content:
                  application/json:
                    schema:
                      $ref: '#/components/schemas/User'
        YAML
                                                                                       ))
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @request #/components/requestBodies/UserBody
          def create
          end
        RUBY
      end

      let(:routes) do
        { "POST /users" => "UsersController#create" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "schemas" => { "User" => { "type" => "object", "properties" => { "id" => { "type" => "integer", "format" => "int64" }, "name" => { "type" => "string" } } } }, "requestBodies" => { "UserBody" => { "description" => "A JSON object containing user information", "required" => true, "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/User" } } } } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } }, "requestBody" => { "$ref" => "#/components/requestBodies/UserBody" } } } } })
      end
    end

    context "with shared scheme reference" do
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
        YAML
                                                                                       ))
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @request #/components/schemas/User
          def create
          end
        RUBY
      end

      let(:routes) do
        { "POST /users" => "UsersController#create" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "schemas" => { "User" => { "type" => "object", "properties" => { "id" => { "type" => "integer", "format" => "int64" }, "name" => { "type" => "string" } } } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } }, "requestBody" => { "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/User" } } } } } } } })
      end
    end

    context "with an invalid tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @request {]}
          def create
          end
        RUBY
      end

      let(:routes) do
        { "POST /users" => "UsersController#create" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized `@request` tag detected/)
        subject
      end
    end

    context "with a duplicate tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @request { email: String, password: String }
          # @request { uuid: String }
          def create
          end
        RUBY
      end

      let(:routes) do
        { "POST /users" => "UsersController#create" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } }, "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "email" => { "type" => "string" }, "password" => { "type" => "string" } } } } } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/duplicate `@request` tag detected/)
        subject
      end
    end
  end
end

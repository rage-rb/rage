# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@auth" do
    context "with before_action" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with skip_before_action" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([])
        allow(RageController::API).to receive(:__before_actions_for).with(:create).and_return([{ name: :authenticate! }])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with different security schemes" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:auth_read).and_return(true)
        allow(RageController::API).to receive(:__before_action_exists?).with(:auth_create).and_return(true)

        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :auth_read }])
        allow(RageController::API).to receive(:__before_actions_for).with(:create).and_return([{ name: :auth_create }])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth auth_read
          # @auth auth_create

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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "auth_read" => { "type" => "http", "scheme" => "bearer" }, "auth_create" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "auth_read" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "auth_create" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multiple security schemes" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:auth_internal).and_return(true)
        allow(RageController::API).to receive(:__before_action_exists?).with(:auth_external).and_return(true)

        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([
          { name: :auth_internal },
          { name: :auth_external }
        ])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth auth_internal
          # @auth auth_external

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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "auth_internal" => { "type" => "http", "scheme" => "bearer" }, "auth_external" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "auth_internal" => [] }, { "auth_external" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with name" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate! ApiKeyAuth

          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "ApiKeyAuth" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "ApiKeyAuth" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with custom definition" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!
          #   type: apiKey
          #   in: header
          #   name: X-API-Key

          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate" => { "type" => "apiKey", "in" => "header", "name" => "X-API-Key" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with shared references" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate_with_token).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate_with_token }])

        allow(Rage::OpenAPI).to receive(:__shared_components).and_return(YAML.safe_load(<<~YAML
          components:
            securitySchemes:
              authenticate:
                type: apiKey
                in: header
                name: X-API-Key
        YAML
                                                                                       ))
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate_with_token

          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate_with_token" => { "type" => "http", "scheme" => "bearer" }, "authenticate" => { "type" => "apiKey", "in" => "header", "name" => "X-API-Key" } } }, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate_with_token" => [] }], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with unused security" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate_with_token).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([])
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate_with_token

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

    context "with inheritance" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_action_exists?).with(:auth_with_token).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :auth_with_token }])
      end

      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!
        RUBY
      end

      let_class("Api::V1::BaseController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # @auth auth_with_token V1-auth
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes["Api::V1::BaseController"]) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let_class("Api::V2::BaseController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # @auth auth_with_token V2-auth
        RUBY
      end

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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "V1-auth" => { "type" => "http", "scheme" => "bearer" }, "V2-auth" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "v1/Users" }, { "name" => "v2/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "V1-auth" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } }, "/api/v2/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "V2-auth" => [] }], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with unknown before action" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(false)
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

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
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/before action `authenticate!` is not defined/)
        subject
      end
    end

    context "with duplicate tag" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # @auth authenticate!

          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /api/v1/users" => "Api::V1::UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "v1/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/duplicate @auth tag detected/)
        subject
      end
    end

    context "with duplicate tag in a difference inheritance chain" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("Api::V1::UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

          def index
          end
        RUBY
      end

      let_class("Api::V2::UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => { "securitySchemes" => { "authenticate" => { "type" => "http", "scheme" => "bearer" } } }, "tags" => [{ "name" => "v1/Users" }, { "name" => "v2/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [{ "authenticate" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } }, "/api/v2/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/duplicate @auth tag detected/)
        subject
      end
    end

    context "with duplicate tag and a custom name" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
        allow(RageController::API).to receive(:__before_actions_for).with(:index).and_return([{ name: :authenticate! }])
      end

      let_class("Api::V1::UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate!

          def index
          end
        RUBY
      end

      let_class("Api::V2::UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate! AuthV2

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

      it "does not log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end

    context "with incorrect name" do
      before do
        allow(RageController::API).to receive(:__before_action_exists?).with(:authenticate!).and_return(true)
      end

      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @auth authenticate! Authenticate By Token

          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/cannot contain spaces/)
        subject
      end
    end
  end
end

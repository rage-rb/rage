# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@summary" do
    context "with summary" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multiple controllers" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let_class("PhotosController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all photos.
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "UsersController#index",
          "GET /photos" => "PhotosController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Photos" }, { "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } }, "/photos" => { "get" => { "summary" => "Returns the list of all photos.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Photos"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with inheritance" do
      let_class("BaseUsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes.BaseUsersController)

      let(:routes) do
        {
          "GET /api/v1/users" => "Api::V1::UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v1/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with inheritance and an override in child controller" do
      let_class("BaseUsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes.BaseUsersController) do
        <<~'RUBY'
          # Returns the list of some users.
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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v1/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "Returns the list of some users.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multiple inheritance chains" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of records.
          def index
          end
        RUBY
      end

      let_class("Api::V1::BaseController", parent: mocked_classes.BaseController) do
        <<~'RUBY'
          # Returns the list of API V1 records.
          def index
          end
        RUBY
      end

      let_class("Api::V1::UsersController", parent: mocked_classes["Api::V1::BaseController"])
      let_class("Api::V2::UsersController", parent: mocked_classes.BaseController)

      let(:routes) do
        {
          "GET /api/v1/users" => "Api::V1::UsersController#index",
          "GET /api/v2/users" => "Api::V2::UsersController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v1/Users" }, { "name" => "v2/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "Returns the list of API V1 records.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } }, "/api/v2/users" => { "get" => { "summary" => "Returns the list of records.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multi-line summary" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users
          #   which were deleted.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "logs error" do
        expect(Rage::OpenAPI).to receive(:__log_warn).with(/summary should only be one line/)
        subject
      end
    end

    context "with empty commments" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # Returns the list of all users.
          #
          # 
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "does not log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end

    context "after another tags" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
          # Returns the list of all users.
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

    context "as the last tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @deprecated
          # @internal this is an internal comment
          #
          # Returns the list of all users.
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

    context "after a text tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @description this is a test description
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "this is a test description", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "does not log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end

    context "after a multi-line tag" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @description this
          #   is
          #   a
          #   test
          #   description
          # Returns the list of all users.
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "Returns the list of all users.", "description" => "this is a test description", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end

      it "does not log error" do
        expect(Rage::OpenAPI).not_to receive(:__log_warn)
        subject
      end
    end
  end
end

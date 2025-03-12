# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new(**options).run }

  let(:options) { {} }

  context "with no routes" do
    let(:routes) { {} }

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [], "paths" => {} })
    end
  end

  context "with a valid controller" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
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

  context "with an invalid controller" do
    let_class("UsersController", parent: Object) do
      <<~'RUBY'
        def index
        end
      RUBY
    end

    let(:routes) do
      { "GET /users" => "UsersController#index" }
    end

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [], "paths" => {} })
    end
  end

  context "with multiple actions" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        def index
        end

        def show
        end
      RUBY
    end

    let(:routes) do
      {
        "GET /users" => "UsersController#index",
        "GET /users/:id" => "UsersController#show"
      }
    end

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } }, "/users/{id}" => { "parameters" => [{ "description" => "", "in" => "path", "name" => "id", "required" => true, "schema" => { "type" => "integer" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
    end
  end

  context "with multiple controllers" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        def index
        end
      RUBY
    end

    let_class("PhotosController", parent: RageController::API) do
      <<~'RUBY'
        def create
        end
      RUBY
    end

    let(:routes) do
      {
        "GET /users" => "UsersController#index",
        "POST /photos" => "PhotosController#create"
      }
    end

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Photos" }, { "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } }, "/photos" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Photos"], "responses" => { "200" => { "description" => "" } } } } } })
    end
  end

  context "with parsing error" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        def index
      RUBY
    end

    let_class("PhotosController", parent: RageController::API) do
      <<~'RUBY'
        def create
        end
      RUBY
    end

    let(:routes) do
      {
        "GET /users" => "UsersController#index",
        "POST /photos" => "PhotosController#create"
      }
    end

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Photos" }], "paths" => { "/photos" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Photos"], "responses" => { "200" => { "description" => "" } } } } } })
    end

    it "logs error" do
      expect(Rage::OpenAPI).to receive(:__log_warn).with("skipping UsersController because of parsing error")
      subject
    end
  end

  context "with namespaces" do
    let_class("Api::V1::UsersController", parent: RageController::API) do
      <<~'RUBY'
        def index
        end
      RUBY
    end

    let_class("Api::V2::UsersController", parent: RageController::API) do
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
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v1/Users" }, { "name" => "v2/Users" }], "paths" => { "/api/v1/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } } }, "/api/v2/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
    end

    context "with a namespace excluded" do
      let(:options) { { namespace: "Api::V2" } }

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "v2/Users" }], "paths" => { "/api/v2/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end
  end

  context "with query parameters" do
    let_class("PhotosController", parent: RageController::API) do
      <<~'RUBY'
        def show
        end
      RUBY
    end

    let(:routes) do
      {
        "GET /users/:user_id/photos/:id" => "PhotosController#show"
      }
    end

    it "returns correct schema" do
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Photos" }], "paths" => { "/users/{user_id}/photos/{id}" => { "parameters" => [{ "description" => "", "in" => "path", "name" => "user_id", "required" => true, "schema" => { "type" => "integer" } }, { "description" => "", "in" => "path", "name" => "id", "required" => true, "schema" => { "type" => "integer" } }], "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Photos"], "responses" => { "200" => { "description" => "" } } } } } })
    end
  end

  context "with invalid tag" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        # @who_am_i
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
      expect(Rage::OpenAPI).to receive(:__log_warn).with(/unrecognized `@who_am_i` tag detected/)
      subject
    end
  end

  context "with multi-line tags" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        # @response 201
        # @description This
        #   is
        #   a test
        #   description.
        # @response 202
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
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "This is a test description.", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "201" => { "description" => "" }, "202" => { "description" => "" } } } } } })
    end
  end

  context "with incorrect multi-line tags" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        # @response 200
        # This is
        # a summary.
        # @response 201
        # @description This
        # is
        # a test
        # description.
        # @response 202
        # @response 404
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
      expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "This is", "description" => "This", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" }, "201" => { "description" => "" }, "202" => { "description" => "" }, "404" => { "description" => "" } } } } } })
    end
  end
end

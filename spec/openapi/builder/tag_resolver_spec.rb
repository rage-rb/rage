# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  before do
    allow(Rage.config.openapi).to receive(:tag_resolver).and_return(tag_resolver)
  end

  describe "custom tag resolver" do
    context "with a custom tag" do
      let(:tag_resolver) do
        proc { "User_Records" }
      end

      let_class("Api::V1::UsersController", parent: RageController::API) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "Api::V1::UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "User_Records" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["User_Records"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with multiple custom tags" do
      let(:tag_resolver) do
        proc { %w(Users Records) }
      end

      let_class("Api::V1::UsersController", parent: RageController::API) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let(:routes) do
        { "GET /users" => "Api::V1::UsersController#index" }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Records" }, { "name" => "Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users", "Records"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with conditionals" do
      let(:tag_resolver) do
        proc do |controller, action, default_tag|
          if controller.name == "Api::V1::PhotosController"
            "UserRecords"
          elsif action == :create
            "ModifyOperations"
          else
            default_tag
          end
        end
      end

      let_class("Api::V1::UsersController", parent: RageController::API) do
        <<~'RUBY'
          def index
          end

          def create
          end
        RUBY
      end

      let_class("Api::V1::PhotosController", parent: RageController::API) do
        <<~'RUBY'
          def index
          end
        RUBY
      end

      let(:routes) do
        {
          "GET /users" => "Api::V1::UsersController#index",
          "POST /users" => "Api::V1::UsersController#create",
          "GET /photos" => "Api::V1::PhotosController#index"
        }
      end

      it "returns correct schema" do
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "ModifyOperations" }, { "name" => "UserRecords" }, { "name" => "v1/Users" }], "paths" => { "/users" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "" } } }, "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["ModifyOperations"], "responses" => { "200" => { "description" => "" } } } }, "/photos" => { "get" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["UserRecords"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end
  end
end

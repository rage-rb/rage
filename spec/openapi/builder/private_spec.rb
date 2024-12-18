# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Builder do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject { described_class.new.run }

  describe "@private" do
    context "with an private method" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @private
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

    context "with multiple methods" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @private
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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [{ "name" => "Users" }], "paths" => { "/users" => { "post" => { "summary" => "", "description" => "", "deprecated" => false, "security" => [], "tags" => ["Users"], "responses" => { "200" => { "description" => "" } } } } } })
      end
    end

    context "with private parent" do
      let_class("BaseController", parent: RageController::API) do
        <<~'RUBY'
          # @private
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
        expect(subject).to eq({ "openapi" => "3.0.0", "info" => { "version" => "1.0.0", "title" => "Rage" }, "components" => {}, "tags" => [], "paths" => {} })
      end
    end

    context "with private comments" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @private External clients should use the Members API
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

    context "with multi-line private comments" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @private External clients
          #   should use the
          #   Members API
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

    context "with multi-line private comments on the class level" do
      let_class("UsersController", parent: RageController::API) do
        <<~'RUBY'
          # @private External clients
          #   should use the
          #   Members API

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
  end
end

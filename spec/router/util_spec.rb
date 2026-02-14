# frozen_string_literal: true

RSpec.describe Rage::Router::Util do
  describe "#path_to_class" do
    let(:klass) { Class.new }

    context "with one section" do
      before do
        stub_const("UsersController", klass)
      end

      it "correctly converts string to class" do
        expect(described_class.path_to_class("users")).to eq(klass)
      end
    end

    context "with multiple sections" do
      before do
        stub_const("AdminUsersController", klass)
      end

      it "correctly converts string to class" do
        expect(described_class.path_to_class("admin_users")).to eq(klass)
      end
    end

    context "with a namespace" do
      before do
        stub_const("Api::UsersController", klass)
      end

      it "correctly converts string to class" do
        expect(described_class.path_to_class("api/users")).to eq(klass)
      end
    end

    context "with multiple namespaces" do
      before do
        stub_const("Admin::Api::V1::UsersController", klass)
      end

      it "correctly converts string to class" do
        expect(described_class.path_to_class("admin/api/v1/users")).to eq(klass)
      end
    end

    context "with multiple namespaces and sections" do
      before do
        stub_const("Api::V1::FavoritePhotosController", klass)
      end

      it "correctly converts string to class" do
        expect(described_class.path_to_class("api/v1/favorite_photos")).to eq(klass)
      end
    end

    context "with incorrect name" do
      before do
        stub_const("UsersController", klass)
      end

      it "raises an error" do
        expect { described_class.path_to_class("api/v1/users") }.to raise_error(Rage::Errors::RouterError)
      end
    end
  end

  describe "#path_to_name" do
    it "correctly converts string to class name" do
      expect(described_class).to receive(:path_to_class).once.and_return(double(name: "test-name"))

      expect(described_class.path_to_name("test")).to eq("test-name")
      expect(described_class.path_to_name("test")).to eq("test-name")
    end
  end

  describe "#route_uri_pattern" do
    let(:users_controller) { double }

    let(:routes) do
      [
        {
          method: "GET",
          path: "/users",
          meta: { controller: "users", action: "index", controller_class: users_controller }
        },
        {
          method: "GET",
          path: "/users/:id",
          meta: { controller: "users", action: "show", controller_class: users_controller }
        }
      ]
    end

    it "returns the path property" do
      expect(Rage.__router).to receive(:routes).and_return(routes)
      expect(described_class.route_uri_pattern(users_controller, "show")).to eq("/users/:id")
    end

    it "caches the result" do
      expect(Rage.__router).to receive(:routes).and_return(routes).once
      2.times { described_class.route_uri_pattern(users_controller, "show") }
    end
  end
end

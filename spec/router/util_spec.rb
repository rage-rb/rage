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

  describe "#path_for" do
    let(:users_controller) { double }

    before do
      described_class.class_variable_set(:@@path_builders, Hash.new { |h, k| h[k] = {} })
      allow(Rage.__router).to receive(:routes).and_return(routes)
    end

    context "with no params" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/users",
            params: [],
            meta: { controller: "users", action: "index" }
          }
        ]
      end

      it "returns the path" do
        expect(described_class.path_for(controller: "users", action: "index")).to eq("/users")
      end
    end

    context "with a single param" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/users/:id",
            params: ["id"],
            meta: { controller: "users", action: "show" }
          }
        ]
      end

      it "returns the path with param substituted" do
        expect(described_class.path_for(controller: "users", action: "show", id: 123)).to eq("/users/123")
      end

      it "raises an error when param is missing" do
        expect { described_class.path_for(controller: "users", action: "show") }.to raise_error(ArgumentError)
      end

      it "raises an error when unexpected param is passed" do
        expect { described_class.path_for(controller: "users", action: "show", id: 123, extra: "value") }.to raise_error(ArgumentError)
      end
    end

    context "with multiple params" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/users/:user_id/posts/:id",
            params: ["user_id", "id"],
            meta: { controller: "posts", action: "show" }
          }
        ]
      end

      it "returns the path with all params substituted" do
        expect(described_class.path_for(controller: "posts", action: "show", user_id: 1, id: 42)).to eq("/users/1/posts/42")
      end
    end

    context "with multiple routes for the same controller/action" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/photos/:id",
            params: ["id"],
            meta: { controller: "photos", action: "show" }
          },
          {
            method: "GET",
            path: "/users/:user_id/photos/:id",
            params: ["user_id", "id"],
            meta: { controller: "photos", action: "show" }
          }
        ]
      end

      it "selects the route matching the provided params" do
        expect(described_class.path_for(controller: "photos", action: "show", id: 5)).to eq("/photos/5")
        expect(described_class.path_for(controller: "photos", action: "show", user_id: 1, id: 5)).to eq("/users/1/photos/5")
      end
    end

    context "with a wildcard route" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/files/*",
            params: ["*"],
            meta: { controller: "files", action: "show" }
          }
        ]
      end

      it "returns the path with wildcard substituted" do
        expect(described_class.path_for(controller: "files", action: "show", wildcard: "path/to/file.txt")).to eq("/files/path/to/file.txt")
      end
    end

    context "when no route is defined" do
      let(:routes) do
        []
      end

      it "raises an ArgumentError" do
        expect { described_class.path_for(controller: "unknown", action: "index") }.to raise_error(ArgumentError, /No route defined/)
      end
    end

    context "multiple calls" do
      let(:routes) do
        [
          {
            method: "GET",
            path: "/users",
            params: [],
            meta: { controller: "users", action: "index" }
          }
        ]
      end

      it "caches the path builders" do
        expect(Rage.__router).to receive(:routes).and_return(routes).once
        2.times { described_class.path_for(controller: "users", action: "index") }
      end
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

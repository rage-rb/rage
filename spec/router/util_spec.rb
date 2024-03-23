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
end

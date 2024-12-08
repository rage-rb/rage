# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::YAML do
  describe "#known_definition?" do
    subject { described_class.new.known_definition?(yaml) }

    context "with object" do
      let(:yaml) do
        "{ status: 'not_found', message: 'Resource Not Found' }"
      end

      it { is_expected.to be(true) }

      context "with an array key" do
        let(:yaml) do
          "{ users: [Hash] }"
        end

        it { is_expected.to be(true) }
      end
    end

    context "with array" do
      context "with one element" do
        let(:yaml) do
          "[String]"
        end

        it { is_expected.to be(true) }
      end

      context "with multiple elements" do
        let(:yaml) do
          "[red, green, blue]"
        end

        it { is_expected.to be(true) }
      end
    end

    context "with invalid yaml" do
      let(:yaml) do
        "[String"
      end

      it { is_expected.to be(false) }
    end

    context "with non-enumerable" do
      let(:yaml) do
        "Hello"
      end

      it { is_expected.to be(false) }
    end
  end

  describe ".parse" do
    subject { described_class.new.parse(yaml) }

    context "with scalar values" do
      let(:yaml) do
        "{ is_error: true, status: 'not_found', code: 404, message: 'Resource Not Found' }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "is_error" => { "type" => "string", "enum" => [true] }, "status" => { "type" => "string", "enum" => ["not_found"] }, "code" => { "type" => "string", "enum" => [404] }, "message" => { "type" => "string", "enum" => ["Resource Not Found"] } } })
      end
    end

    context "with class values" do
      let(:yaml) do
        "{ is_error: Boolean, status: String, code: Integer, message: String }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "is_error" => { "type" => "boolean" }, "status" => { "type" => "string" }, "code" => { "type" => "integer" }, "message" => { "type" => "string" } } })
      end
    end

    context "with unary array" do
      context "with String" do
        let(:yaml) do
          "{ roles: [String] }"
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "roles" => { "type" => "array", "items" => { "type" => "string" } } } })
        end
      end

      context "with Integer" do
        let(:yaml) do
          "{ ids: [Integer] }"
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "ids" => { "type" => "array", "items" => { "type" => "integer" } } } })
        end
      end

      context "with Hash" do
        let(:yaml) do
          "{ users: [Hash] }"
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "users" => { "type" => "array", "items" => { "type" => "object" } } } })
        end
      end
    end

    context "with non-unary array" do
      let(:yaml) do
        "{ colors: [red, green, blue] }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "colors" => { "type" => "string", "enum" => ["red", "green", "blue"] } } })
      end
    end

    context "with objects inside array" do
      let(:yaml) do
        "{ users: [{ id: Integer, name: String, is_active: Boolean, comments: [{ id: Integer, content: String }] }] }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "name" => { "type" => "string" }, "is_active" => { "type" => "boolean" }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "content" => { "type" => "string" } } } } } } } } })
      end
    end

    context "with arrays inside arrays" do
      let(:yaml) do
        "{ users: [{ id: Integer, data: { comments: [{ status: [is_active, is_edited, is_deleted] }], friend_names: [String] } }] }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "data" => { "type" => "object", "properties" => { "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "status" => { "type" => "string", "enum" => ["is_active", "is_edited", "is_deleted"] } } } }, "friend_names" => { "type" => "array", "items" => { "type" => "string" } } } } } } } } })
      end
    end

    context "with objects inside objects" do
      let(:yaml) do
        "{ user: { id: Integer, avatar: { url: String, width: Integer, height: Integer }, geo: { lat: Float, lng: Float } } }"
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" }, "width" => { "type" => "integer" }, "height" => { "type" => "integer" } } }, "geo" => { "type" => "object", "properties" => { "lat" => { "type" => "number", "format" => "float" }, "lng" => { "type" => "number", "format" => "float" } } } } } } })
      end
    end
  end
end

# frozen_string_literal: true

require "active_record"

RSpec.describe Rage::OpenAPI::Parsers::Ext::ActiveRecord do
  before :all do
    skip("skipping external tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"

    ActiveRecord::Base.establish_connection(url: ENV["TEST_PG_URL"])
    setup_test_schema
  end

  after :all do
    ActiveRecord::Base.connection.disconnect!
  end

  def setup_test_schema
    ActiveRecord::Base.connection.create_table :open_api_test_products, force: true do |t|
      t.string :name
      t.decimal :price
      t.integer :quantity
      t.float :weight
      t.boolean :available
      t.text :description
      t.json :metadata
      t.date :release_date
      t.datetime :published_at
      t.time :scheduled_time
      t.binary :image
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_orders, force: true do |t|
      t.string :status
      t.integer :priority
      t.string :email
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_comments, force: true do |t|
      t.text :body
      t.integer :openapi_test_product_id
      t.integer :author_id
      t.integer :rating
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_vehicles, force: true do |t|
      t.string :type
      t.string :brand
      t.string :model_name
      t.integer :doors
      t.integer :cargo_capacity
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_users, force: true do |t|
      t.string :username
      t.string :email
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_empty_models, force: true do |t|
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :open_api_test_blacklisted_models, force: true do |t|
      t.timestamps
    end
  end

  module OpenApiParserSpec
    class OpenAPITestProduct < ActiveRecord::Base
    end

    # Enums
    class OpenAPITestOrder < ActiveRecord::Base
      enum :status, { pending: "pending", processing: "processing", completed: "completed", cancelled: "cancelled" }
      enum :priority, { low: 0, medium: 1, high: 2 }
    end

    # Foreign Keys
    class OpenAPITestComment < ActiveRecord::Base
    end

    # STI
    class OpenAPITestVehicle < ActiveRecord::Base
    end

    class OpenAPITestCar < OpenAPITestVehicle
    end

    class OpenAPITestTruck < OpenAPITestVehicle
    end

    # Namespace
    module Api
      module V1
        class OpenAPITestUser < ActiveRecord::Base
          self.table_name = "openapi_test_users"
        end
      end
    end

    # Empty
    class OpenAPITestEmptyModel < ActiveRecord::Base
    end

    # Only blacklisted attributes
    class OpenAPITestBlacklistedModel < ActiveRecord::Base
    end
  end

  describe "#known_definition?" do
    subject { described_class.new }

    it "returns true for ActiveRecord models" do
      expect(subject.known_definition?("OpenApiParserSpec::OpenAPITestProduct")).to be true
    end

    it "returns true for AR models in array notation" do
      expect(subject.known_definition?("[OpenApiParserSpec::OpenAPITestProduct]")).to be true
    end

    it "returns true for AR models in Array<> notation" do
      expect(subject.known_definition?("Array<OpenApiParserSpec::OpenAPITestProduct>")).to be true
    end

    it "returns false for non-existent classes" do
      expect(subject.known_definition?("NonExistentModel")).to be false
    end

    it "returns false for non-AR classes" do
      expect(subject.known_definition?("String")).to be false
    end

    context "with namespace" do
      subject { described_class.new(namespace: OpenApiParserSpec::Api::V1) }

      it "resolves models within the namespace" do
        expect(subject.known_definition?("OpenAPITestUser")).to be true
      end
    end

    context "with empty namespace" do
      subject { described_class.new(namespace: OpenApiParserSpec::Api) }

      it "resolves models within the namespace" do
        expect(subject.known_definition?("OpenAPITestUser")).to be false
      end
    end
  end

  describe "#parse" do
    subject { described_class.new }

    context "type mappings" do
      let(:schema) { subject.parse("OpenApiParserSpec::OpenAPITestProduct") }
      let(:properties) { schema["properties"] }

      it "maps string columns to string type" do
        expect(properties["name"]).to eq({ "type" => "string" })
      end

      it "maps integer columns to integer type" do
        expect(properties["quantity"]).to eq({ "type" => "integer" })
      end

      it "maps decimal columns to number type" do
        expect(properties["price"]).to eq({ "type" => "number" })
      end

      it "maps float columns to number type with float format" do
        expect(properties["weight"]).to eq({ "type" => "number", "format" => "float" })
      end

      it "maps boolean columns to boolean type" do
        expect(properties["available"]).to eq({ "type" => "boolean" })
      end

      it "maps json columns to object type" do
        expect(properties["metadata"]).to eq({ "type" => "object" })
      end

      it "maps date columns to string with date format" do
        expect(properties["release_date"]).to eq({ "type" => "string", "format" => "date" })
      end

      it "maps datetime columns to string with date-time format" do
        expect(properties["published_at"]).to eq({ "type" => "string", "format" => "date-time" })
      end

      it "maps time columns to string with date-time format" do
        expect(properties["scheduled_time"]).to eq({ "type" => "string", "format" => "date-time" })
      end

      it "maps binary columns to string with binary format" do
        expect(properties["image"]).to eq({ "type" => "string", "format" => "binary" })
      end

      it "maps text columns to string type" do
        expect(properties["description"]).to eq({ "type" => "string" })
      end
    end

    context "attribute filtering" do
      let(:schema) { subject.parse("OpenApiParserSpec::OpenAPITestProduct") }
      let(:properties) { schema["properties"] }

      it "filters id attribute" do
        expect(properties).not_to have_key("id")
      end

      it "filters created_at attribute" do
        expect(properties).not_to have_key("created_at")
      end

      it "filters updated_at attribute" do
        expect(properties).not_to have_key("updated_at")
      end

      it "filters foreign keys ending with _id" do
        comment_schema = subject.parse("OpenApiParserSpec::OpenAPITestComment")
        comment_properties = comment_schema["properties"]

        expect(comment_properties).not_to have_key("openapi_test_product_id")
        expect(comment_properties).not_to have_key("author_id")
      end

      it "includes regular integer attributes that don't end with _id" do
        comment_schema = subject.parse("OpenApiParserSpec::OpenAPITestComment")
        comment_properties = comment_schema["properties"]

        expect(comment_properties).to have_key("rating")
        expect(comment_properties["rating"]).to eq({ "type" => "integer" })
      end

      it "includes regular attributes" do
        expect(properties).to have_key("name")
        expect(properties).to have_key("price")
        expect(properties).to have_key("quantity")
      end
    end

    context "enums" do
      let(:schema) { subject.parse("OpenApiParserSpec::OpenAPITestOrder") }
      let(:properties) { schema["properties"] }

      it "includes string enum with allowed values" do
        expect(properties["status"]).to eq({
          "type" => "string",
          "enum" => ["pending", "processing", "completed", "cancelled"]
        })
      end

      it "includes integer-backed enum with string keys" do
        expect(properties["priority"]).to eq({
          "type" => "string",
          "enum" => ["low", "medium", "high"]
        })
      end

      it "does not add enum attributes as both enum and regular types" do
        status_count = properties.select { |k, v| k == "status" }.count
        priority_count = properties.select { |k, v| k == "priority" }.count

        expect(status_count).to eq(1)
        expect(priority_count).to eq(1)
      end

      it "processes non-enum string attributes normally" do
        expect(properties["email"]).to eq({ "type" => "string" })
      end
    end

    context "collections" do
      it "wraps array notation in array schema" do
        schema = subject.parse("[OpenApiParserSpec::OpenAPITestProduct]")

        expect(schema["type"]).to eq("array")
        expect(schema["items"]["type"]).to eq("object")
        expect(schema["items"]["properties"]).to have_key("name")
      end

      it "wraps Array<> notation in array schema" do
        schema = subject.parse("Array<OpenApiParserSpec::OpenAPITestProduct>")

        expect(schema["type"]).to eq("array")
        expect(schema["items"]["type"]).to eq("object")
        expect(schema["items"]["properties"]).to have_key("name")
      end

      it "applies filtering to array items" do
        schema = subject.parse("[OpenApiParserSpec::OpenAPITestProduct]")
        items = schema["items"]["properties"]

        expect(items).not_to have_key("id")
        expect(items).not_to have_key("created_at")
      end
    end

    context "Single Table Inheritance" do
      it "filters inheritance column in parent class" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestVehicle")
        properties = schema["properties"]

        expect(properties).not_to have_key("type")
        expect(properties).to have_key("brand")
        expect(properties).to have_key("model_name")
      end

      it "filters inheritance column in child class" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestCar")
        properties = schema["properties"]

        expect(properties).not_to have_key("type")
      end

      it "includes subclass-specific attributes in child" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestCar")
        properties = schema["properties"]

        expect(properties).to have_key("doors")
        expect(properties["doors"]).to eq({ "type" => "integer" })
      end

      it "includes shared attributes in child class" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestTruck")
        properties = schema["properties"]

        expect(properties).to have_key("brand")
        expect(properties).to have_key("model_name")
        expect(properties).to have_key("cargo_capacity")
      end
    end

    context "namespace resolution" do
      subject { described_class.new(namespace: OpenApiParserSpec::Api::V1) }

      it "resolves models within custom namespace" do
        schema = subject.parse("OpenAPITestUser")
        properties = schema["properties"]

        expect(properties).to have_key("username")
        expect(properties).to have_key("email")
      end

      it "works with collections in namespaced context" do
        schema = subject.parse("[OpenAPITestUser]")

        expect(schema["type"]).to eq("array")
        expect(schema["items"]["properties"]).to have_key("username")
      end
    end

    context "edge cases" do
      it "returns object type for models with no attributes" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestEmptyModel")

        expect(schema["type"]).to eq("object")
        expect(schema["properties"]).to be_nil
      end

      it "returns object type for models with only blacklisted attributes" do
        schema = subject.parse("OpenApiParserSpec::OpenAPITestBlacklistedModel")

        expect(schema["type"]).to eq("object")
        expect(schema["properties"]).to be_nil
      end
    end
  end
end

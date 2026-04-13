# frozen_string_literal: true

RSpec.describe "Rage::OpenAPI cache leakage" do
  include_context "mocked_rage_routes"

  let(:routes) { {} }

  it "clears the schema registry when Builder#run is called" do
    # Manually populate the registry
    Rage::OpenAPI.__schema_registry["UserResource"] = { "type" => "object" }
    expect(Rage::OpenAPI.__schema_registry).not_to be_empty

    # Run the builder, which should trigger __reset_data_cache
    Rage::OpenAPI::Builder.new.run

    expect(Rage::OpenAPI.__schema_registry).to be_empty
  end
end

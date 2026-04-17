# frozen_string_literal: true

require "prism"

RSpec.describe "Rage::OpenAPI registry isolation" do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  let_class("UserResource") do
    <<~RUBY
      include Alba::Resource
      attributes :id
    RUBY
  end

  let_class("UsersController", parent: RageController::API) do
    <<~RUBY
      # @response {Any} UserResource
      def index; end
    RUBY
  end

  let(:routes) do
    { "GET /users" => "UsersController#index" }
  end

  it "does not use a global registry for circular definitions" do
    # Build the spec
    Rage::OpenAPI.build

    # The global registry should remain empty because we used the Root node's registry
    expect(Rage::OpenAPI.__schema_registry).to be_empty
  end
end

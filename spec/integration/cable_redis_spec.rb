# frozen_string_literal: true

require "websocket-client-simple"

RSpec.describe "Cable Redis" do
  before :all do
    skip("skipping cable redis tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: { "ENABLE_REDIS_ADAPTER" => "1" })
  end

  after :all do
    stop_server
  end

  it "broadcasts messages using the adapter" do
    client = with_websocket_connection("ws://localhost:3000/cable/time?user_id=1", headers: { Origin: "localhost:3000" })

    Bundler.with_unbundled_env do
      system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); Rage.cable.broadcast(\"current_time\", { message: \"hello from another process\" })'", chdir: "spec/integration/test_app")
    end

    expect(client.messages.last).to include("hello from another process")
  end
end

# frozen_string_literal: true

RSpec.describe "Isolated Apps" do
  before :all do
    skip("skipping websocket tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: {
      "WEBSOCKETS_PROTOCOL" => "actioncable_v1_json",
      "ENABLE_ISOLATED_CABLE_APPS" => "1",
      "ENABLE_REDIS_ADAPTER" => "1"
    })
  end

  after :all do
    stop_server
  end

  let(:headers) { { Origin: "localhost:3000" } }

  it "rejects a connection with no account_id" do
    with_websocket_connection("ws://localhost:3000/presence_raw/status", headers:) do |client|
      expect(client.messages[0]).to include("unauthorized")
    end
  end

  it "opens a connection" do
    with_websocket_connection("ws://localhost:3000/presence_raw/status?account_id=1", headers:) do |client|
      expect(client.messages).to be_empty
      expect(client).to be_connected
    end
  end

  it "broadcasts messages to a specific app" do
    client = with_websocket_connection("ws://localhost:3000/presence_raw/status?account_id=1", headers:)

    Bundler.with_unbundled_env do
      system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); Rage.cable.broadcast(\"presence\", { is_present: true })'", chdir: "spec/integration/test_app")
    end

    expect(client.messages.last).to include("is_present")
  end

  it "broadcasts messages between apps respecting protocols" do
    client_raw = with_websocket_connection("ws://localhost:3000/presence_raw/status?account_id=1", headers:)

    client_ac = with_websocket_connection("ws://localhost:3000/presence_ac/status", headers:)
    client_ac.send({ identifier: { client: "1", channel: "StatusChannel" }.to_json, command: "subscribe" }.to_json)

    Bundler.with_unbundled_env do
      system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); Rage.cable.broadcast(\"presence\", { is_present: true })'", chdir: "spec/integration/test_app")
    end

    expect(client_raw.messages.last).to eq({ is_present: true }.to_json)
    expect(client_ac.messages.last).to match(/channel\W+StatusChannel\W+message\W+is_present\W+true/)
  end
end

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

  it "rejects a connection with no account_id" do
    create_ws_client("ws://localhost:3000/presence_raw/status") do |client|
      expect(client.receive).to include("unauthorized")
    end
  end

  it "opens a connection" do
    create_ws_client("ws://localhost:3000/presence_raw/status?account_id=1") do |client|
      expect(client).to be_connected
      expect(client.receive).to include("ok")
    end
  end

  it "broadcasts messages to a specific app" do
    create_ws_client("ws://localhost:3000/presence_raw/status?account_id=1") do |client|
      Bundler.with_unbundled_env do
        system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); Rage.cable.broadcast(\"presence\", { is_present: true })'", chdir: "spec/integration/test_app")
      end

      2.times { client.receive }

      expect(client.last_message).to include("is_present")
    end
  end

  it "broadcasts messages between apps respecting protocols" do
    client_raw = create_ws_client("ws://localhost:3000/presence_raw/status?account_id=1")
    client_raw.receive

    client_ac = create_ws_client("ws://localhost:3000/presence_ac/status")
    client_ac.send({ identifier: { client: "1", channel: "StatusChannel" }.to_json, command: "subscribe" }.to_json)
    3.times { client_ac.receive }

    Bundler.with_unbundled_env do
      system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); Rage.cable.broadcast(\"presence\", { is_present: true })'", chdir: "spec/integration/test_app")
    end

    expect(client_raw.receive).to eq({ is_present: true }.to_json)
    expect(client_ac.receive).to match(/channel\W+StatusChannel\W+message\W+is_present\W+true/)

  ensure
    client_raw.close
    client_ac.close
  end
end

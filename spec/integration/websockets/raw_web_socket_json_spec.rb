# frozen_string_literal: true

RSpec.describe "RawWebSocketJson" do
  before :all do
    skip("skipping websocket tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: { "WEBSOCKETS_PROTOCOL" => "raw_websocket_json" })
  end

  after :all do
    stop_server
  end

  it "rejects a connection with no user_id" do
    create_ws_client("ws://localhost:3000/cable/time") do |client|
      expect(client.receive).to eq({ err: "unauthorized" }.to_json)
    end
  end

  it "correctly derives channel name from URL" do
    create_ws_client("ws://localhost:3000/cable/time?user_id=1") do |client|
      expect(client).to be_connected
      expect(client.receive).to include("sending_current_time")
    end
  end

  it "correctly derives complex channel name from URL" do
    create_ws_client("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=1") do |client|
      expect(client).to be_connected
    end
  end

  it "doesn't transform channel names as classes" do
    create_ws_client("ws://localhost:3000/cable/MultiplyNumbersChannel?user_id=1&multiplier=1") do |client|
      expect(client).to be_connected
    end
  end

  it "rejects incorrect channel names" do
    create_ws_client("ws://localhost:3000/cable/incorrect_channel?user_id=1") do |client|
      expect(client.receive).to eq({ err: "invalid channel name" }.to_json)
    end
  end

  it "receives messages from the server" do
    create_ws_client("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=6") do |client|
      client.send({ i: 4 }.to_json)
      expect(client.receive).to eq({ result: 24 }.to_json)
    end
  end

  it "processes pings" do
    create_ws_client("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=1") do |client|
      client.send("ping")
      expect(client.receive(heartbeat: true)).to eq("pong")
    end
  end

  it "correctly rejects subscriptions" do
    create_ws_client("ws://localhost:3000/cable/multiply_numbers?user_id=1") do |client|
      expect(client.receive).to eq({ err: "subscription rejected" }.to_json)
    end
  end
end

# frozen_string_literal: true

RSpec.describe "RawWebsocketJson" do
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
    with_websocket_connection("ws://localhost:3000/cable/time", headers: { Origin: "localhost:3000" }) do |client|
      expect(client.messages[0]).to eq({ err: "unauthorized" }.to_json)
    end
  end

  it "correctly derives channel name from URL" do
    with_websocket_connection("ws://localhost:3000/cable/time?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client).to be_connected

      expect(client.messages.count).to eq(1)
      expect(client.messages[0]).to include("sending_current_time")
    end
  end

  it "correctly derives complex channel name from URL" do
    with_websocket_connection("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client).to be_connected
      expect(client.messages).to be_empty
    end
  end

  it "doesn't transform channel names as classes" do
    with_websocket_connection("ws://localhost:3000/cable/MultiplyNumbersChannel?user_id=1&multiplier=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client).to be_connected
      expect(client.messages).to be_empty
    end
  end

  it "rejects incorrect channel names" do
    with_websocket_connection("ws://localhost:3000/cable/incorrect_channel?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client.messages[0]).to eq({ err: "invalid channel name" }.to_json)
    end
  end

  it "receives messages from the server" do
    with_websocket_connection("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=6", headers: { Origin: "localhost:3000" }) do |client|
      client.send({ i: 4 }.to_json)
      expect(client.messages[0]).to eq({ result: 24 }.to_json)
    end
  end

  it "processes pings" do
    with_websocket_connection("ws://localhost:3000/cable/multiply_numbers?user_id=1&multiplier=1", headers: { Origin: "localhost:3000" }) do |client|
      client.send("ping")
      sleep 1
      expect(client.messages[0]).to eq("pong")
    end
  end

  it "correctly rejects subscriptions" do
    with_websocket_connection("ws://localhost:3000/cable/multiply_numbers?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client.messages[0]).to eq({ err: "subscription rejected" }.to_json)
    end
  end
end

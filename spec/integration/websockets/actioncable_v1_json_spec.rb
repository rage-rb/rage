# frozen_string_literal: true

RSpec.describe "Actioncable" do
  before :all do
    skip("skipping websocket tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: { "WEBSOCKETS_PROTOCOL" => "actioncable_v1_json" })
  end

  after :all do
    stop_server
  end

  let(:subscribe_message) { { identifier: { client: "1", channel: "TimeChannel" }.to_json, command: "subscribe" }.to_json }
  let(:get_time_message) { { identifier: { client: "1", channel: "TimeChannel" }.to_json, command: "message", data: { action: "what_time_is_it" }.to_json }.to_json }
  let(:sync_time_message) { { identifier: { client: "1", channel: "TimeChannel" }.to_json, command: "message", data: { action: "sync_time" }.to_json }.to_json }
  let(:remote_sync_time_message) { { identifier: { client: "1", channel: "TimeChannel" }.to_json, command: "message", data: { action: "remote_sync_time", remote: "time.com" }.to_json }.to_json }

  it "rejects a connection from unknown origin" do
    with_websocket_connection("ws://localhost:3000/cable") do |client|
      expect(client).not_to be_connected
    end
  end

  it "rejects a connection with no user_id" do
    with_websocket_connection("ws://localhost:3000/cable", headers: { Origin: "localhost:3000" }) do |client|
      expect(client.messages[0]).to include("unauthorized")
    end
  end

  it "opens a connection" do
    with_websocket_connection("ws://localhost:3000/cable?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      expect(client.messages.count).to eq(1)
      expect(client.messages[0]).to include("welcome")
    end
  end

  it "subscribes to a channel" do
    with_websocket_connection("ws://localhost:3000/cable?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      client.send(subscribe_message)
      expect(client.messages.count).to eq(3)
      expect(client.messages[1]).to include("confirm_subscription")
      expect(client.messages[2]).to include("sending_current_time")
    end
  end

  it "receives messages from the server" do
    with_websocket_connection("ws://localhost:3000/cable?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      client.send(subscribe_message)
      client.send(get_time_message)
      expect(client.messages.last).to include("transmitting_current_time")
    end
  end

  it "receives broadcasts from the server" do
    with_websocket_connection("ws://localhost:3000/cable?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
      client.send(subscribe_message)
      client.send(sync_time_message)
      expect(client.messages.last).to include("broadcasting_current_time")
    end
  end

  it "receives broadcasts from the server" do
    Thread.new do
      with_websocket_connection("ws://localhost:3000/cable?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
        client.send(subscribe_message)
        client.send(sync_time_message)
      end
    end

    with_websocket_connection("ws://localhost:3000/cable?user_id=2", headers: { Origin: "localhost:3000" }) do |client|
      client.send(subscribe_message)
      sleep 0.1
      expect(client.messages.last).to include("broadcasting_current_time")
      expect(client.messages.last).to include("initiated by user 1")
    end
  end

  it "requires a subscription to interact with a channel" do
    with_websocket_connection("ws://localhost:3000/cable?user_id=2", headers: { Origin: "localhost:3000" }) do |client|
      client.send(get_time_message)
      expect(client.messages.last).to include("invalid_request")
    end
  end

  it "processes messages asynchronously" do
    skip if ENV["GITHUB_ACTIONS"]

    threads = 3.times.map do
      Thread.new do
        with_websocket_connection("ws://localhost:3000/cable?user_id=#{rand(100)}", headers: { Origin: "localhost:3000" }) do |client|
          client.send(subscribe_message)
          client.send(remote_sync_time_message)
        end
      end
    end

    sleep 1.5

    threads.each do |thread|
      client = thread.value
      expect(client.messages.last).to include("synced from time.com")
    end
  end
end

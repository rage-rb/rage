# frozen_string_literal: true

require "benchmark"

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
  let(:unsubscribe_message) { { identifier: { client: "1", channel: "TimeChannel" }.to_json, command: "unsubscribe" }.to_json }

  it "rejects a connection from unknown origin" do
    create_ws_client("ws://localhost:3000/cable", headers: {}) do |client|
      expect(client).not_to be_connected
    end
  end

  it "rejects a connection with no user_id" do
    create_ws_client("ws://localhost:3000/cable") do |client|
      expect(client.receive).to include("unauthorized")
    end
  end

  it "opens a connection" do
    create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
      expect(client.receive).to include("welcome")
    end
  end

  it "subscribes to a channel" do
    create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
      client.send(subscribe_message)
      messages = 3.times.map { client.receive }

      expect(messages[1]).to include("confirm_subscription")
      expect(messages[2]).to include("sending_current_time")
    end
  end

  it "receives messages from the server" do
    create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
      client.send(subscribe_message)
      client.send(get_time_message)
      4.times { client.receive }

      expect(client.last_message).to include("transmitting_current_time")
    end
  end

  it "receives broadcasts from the server" do
    create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
      client.send(subscribe_message)
      client.send(sync_time_message)
      4.times { client.receive }

      expect(client.last_message).to include("broadcasting_current_time")
    end
  end

  it "receives broadcasts from the server" do
    create_ws_client("ws://localhost:3000/cable?user_id=2") do |client|
      client.send(subscribe_message)
      3.times { client.receive }

      Thread.new {
        create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
          client.send(subscribe_message)
          client.send(sync_time_message)
          3.times { client.receive }
        end
      }.join

      client.receive
      expect(client.last_message).to include("broadcasting_current_time")
      expect(client.last_message).to include("initiated by user 1")
    end
  end

  it "requires a subscription to interact with a channel" do
    create_ws_client("ws://localhost:3000/cable?user_id=2") do |client|
      client.send(get_time_message)
      2.times { client.receive }
      expect(client.last_message).to include("invalid_request")
    end
  end

  it "processes messages asynchronously" do
    clients = 5.times.map do
      client = create_ws_client("ws://localhost:3000/cable?user_id=#{rand(100)}")
      client.send(subscribe_message)
      3.times { client.receive }

      client
    end

    clients.each do |client|
      client.send(remote_sync_time_message)
    end

    time_spent = Benchmark.realtime do
      clients.map { |client| Thread.new { client.receive } }.each(&:join)
    end

    clients.each do |client|
      expect(client.last_message).to include("synced from time.com")
    end

    expect(time_spent).to be < 2
  ensure
    clients.each(&:close)
  end

  it "unsubscribes from streams" do
    create_ws_client("ws://localhost:3000/cable?user_id=1") do |client|
      client.send(subscribe_message)
      client.send(unsubscribe_message)
      4.times { client.receive }

      expect(client.last_message).to include("unsubscribed")
    end
  end
end

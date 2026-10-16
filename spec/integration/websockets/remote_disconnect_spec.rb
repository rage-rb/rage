# frozen_string_literal: true

require "http"

RSpec.describe "RemoteDisconnect" do
  before :all do
    skip("skipping websocket tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  context "with Redis adapter" do
    before :all do
      launch_server(env: {
        "WEBSOCKETS_PROTOCOL" => "raw_websocket_json",
        "ENABLE_ISOLATED_CABLE_APPS" => "1",
        "ENABLE_REDIS_ADAPTER" => "1"
      })
    end

    after :all do
      stop_server
    end

    it "disconnects a connection from within the runtime" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to match("ok")

        response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
        expect(response.code).to eq(200)

        expect(client.receive).to eq(:closed)
      end
    end

    it "disconnects a connection from outside the runtime" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to match("ok")

        Bundler.with_unbundled_env do
          system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); RageCable::Connection.disconnect(current_user: \"123\")'", chdir: "spec/integration/test_app")
        end

        expect(client.receive).to eq(:closed)
      end
    end

    it "doesn't fail with non-existend ids" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to match("ok")

        response = HTTP.post("http://localhost:3000/cable_close?user_id=7890")
        expect(response.code).to eq(200)

        expect(client.receive).to be_nil
        expect(client).to be_connected
      end
    end

    it "doesn't fail for rejected connections" do
      create_ws_client("ws://localhost:3000/cable/logs") do |client|
        2.times { client.receive }
        expect(client.last_message).to eq(:closed)

        response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
        expect(response.code).to eq(200)
      end
    end

    it "doesn't fail for closed connections" do
      create_ws_client("ws://localhost:3000/cable/logs") do |client|
        client.close

        response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
        expect(response.code).to eq(200)
      end
    end

    it "allows to disconnect by one of multiple identifiers" do
      user_client = create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123")
      account_client = create_ws_client("ws://localhost:3000/presence_raw/status?account_id=567")
      other_user_client = create_ws_client("ws://localhost:3000/presence_raw/status?user_id=000")

      [user_client, account_client, other_user_client].each(&:receive)

      response = HTTP.post("http://localhost:3000/cable_close_raw?user_id=123")
      expect(response.code).to eq(200)

      expect(user_client.receive).to eq(:closed)
      expect(account_client.receive).to be_nil
      expect(other_user_client.receive).to be_nil

      expect(account_client).to be_connected
      expect(other_user_client).to be_connected

    ensure
      [user_client, account_client, other_user_client].each(&:close)
    end

    it "disconnects by composite identifiers" do
      create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123&account_id=567") do |client|
        client.receive

        response = HTTP.post("http://localhost:3000/cable_close_raw?user_id=123&account_id=567")
        expect(response.code).to eq(200)

        expect(client.receive).to eq(:closed)
      end
    end

    it "matches one of multiple identifiers" do
      create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123&account_id=567") do |client|
        client.receive

        response = HTTP.post("http://localhost:3000/cable_close_raw?user_id=123")
        expect(response.code).to eq(200)

        expect(client.receive).to eq(:closed)
      end
    end

    it "scopes disconnects to the cable connection class" do
      std_client = create_ws_client("ws://localhost:3000/cable/logs?user_id=123")
      raw_client = create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123")

      std_client.receive
      raw_client.receive

      response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
      expect(response.code).to eq(200)

      expect(std_client.receive).to eq(:closed)
      expect(raw_client.receive).to be_nil
      expect(raw_client).to be_connected

    ensure
      [std_client, raw_client].each(&:close)
    end

    it "disconnects multiple connections for the same identifier" do
      client_1 = create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123")
      client_2 = create_ws_client("ws://localhost:3000/presence_raw/status?user_id=123")

      client_1.receive
      client_2.receive

      response = HTTP.post("http://localhost:3000/cable_close_raw?user_id=123")
      expect(response.code).to eq(200)

      expect(client_1.receive).to eq(:closed)
      expect(client_2.receive).to eq(:closed)

    ensure
      [client_1, client_2].each(&:close)
    end
  end

  context "without Redis adapter" do
    before :all do
      launch_server(env: {
        "WEBSOCKETS_PROTOCOL" => "raw_websocket_json",
        "ENABLE_ISOLATED_CABLE_APPS" => "1"
      })
    end

    after :all do
      stop_server
    end

    it "disconnects a connection from within the runtime" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to match("ok")

        response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
        expect(response.code).to eq(200)

        expect(client.receive).to eq(:closed)
      end
    end

    it "doesn't fail when attempting to disconnect a connection from outside the runtime" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to match("ok")

        Bundler.with_unbundled_env do
          system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e 'require_relative(\"config/application\"); RageCable::Connection.disconnect(current_user: \"123\")'", chdir: "spec/integration/test_app")
        end

        expect(client.receive).to be_nil
      end
    end
  end

  context "with Action Cable protocol" do
    before :all do
      launch_server(env: {
        "WEBSOCKETS_PROTOCOL" => "actioncable_v1_json",
        "ENABLE_ISOLATED_CABLE_APPS" => "1"
      })
    end

    after :all do
      stop_server
    end

    it "sends a disconnect message" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=123") do |client|
        expect(client.receive).to include("welcome")

        response = HTTP.post("http://localhost:3000/cable_close?user_id=123")
        expect(response.code).to eq(200)

        expect(client.receive).to match(/type\W+disconnect\W+reason\W+remote/)
        expect(client.receive).to eq(:closed)
      end
    end
  end
end

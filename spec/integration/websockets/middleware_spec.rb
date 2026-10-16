# frozen_string_literal: true

require "http"

RSpec.describe "Middleware" do
  before :all do
    skip("skipping websocket tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: {
      "RAGE_ENV" => "production",
      "ENABLE_ISOLATED_CABLE_APPS" => "1",
      "WEBSOCKETS_PROTOCOL" => "actioncable_v1_json"
    })
  end

  after :all do
    stop_server
  end

  context "with config.ru mount" do
    it "accepts requests from the same origin" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "https://example.com", Host: "example.com" }) do |client|
        expect(client).to be_connected
        expect(client.receive).to include("welcome")
      end
    end

    it "rejects requests from non-matching origins" do
      create_ws_client("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "https://example.com", Host: "example.net" }) do |client|
        expect(client).not_to be_connected
      end
    end

    it "includes HTTP middleware" do
      response = HTTP.
        headers("Test-Middleware" => "true", Origin: "http://localhost:3000").
        get("http://localhost:3000/cable/logs?user_id=1")

      expect(response.code).to eq(206)
      expect(response.to_s).to eq("response from middleware")
    end

    it "reponds with 404 for non-matching origins" do
      response = HTTP.
        headers(Origin: "http://unknown.com").
        get("http://localhost:3000/cable/logs?user_id=1")

      expect(response.code).to eq(404)
    end
  end

  context "with routes mount" do
    it "accepts requests from the same origin" do
      create_ws_client("ws://localhost:3000/presence_ac/status", headers: { Origin: "https://example.com", Host: "example.com" }) do |client|
        expect(client).to be_connected
        expect(client.receive).to include("welcome")
      end
    end

    it "rejects requests from non-matching origins" do
      create_ws_client("ws://localhost:3000/presence_ac/status", headers: { Origin: "https://example.com", Host: "example.net" }) do |client|
        expect(client).not_to be_connected
      end
    end

    it "includes HTTP middleware" do
      response = HTTP.
        headers("Test-Middleware" => "true", Origin: "http://localhost:3000").
        get("http://localhost:3000/presence_ac/status")

      expect(response.code).to eq(206)
      expect(response.to_s).to eq("response from middleware")
    end

    it "reponds with 404 for non-matching origins" do
      response = HTTP.
        headers(Origin: "http://unknown.com").
        get("http://localhost:3000/presence_ac/status")

      expect(response.code).to eq(404)
    end
  end
end

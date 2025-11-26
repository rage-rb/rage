# frozen_string_literal: true

require "http"

RSpec.describe "Global log context" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

  context "with valid custom context" do
    before :all do
      launch_server(env: { "ENABLE_CUSTOM_LOG_CONTEXT" => "1" })
    end

    after :all do
      stop_server
    end

    it "enriches request logs" do
      HTTP.get("http://localhost:3000/empty")
      expect(logs.last).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/empty controller=ApplicationController action=empty current_time=\d+ status=204 duration=\d+\.\d+$/)
    end

    it "enriches custom logs" do
      HTTP.get("http://localhost:3000/logs/custom")

      request_logs = logs.last(4)
      request_logs.each do |log|
        expect(log).to match(/^\[\w{16}\]\[development\]/)
        expect(log).to match(/current_time=\d+/)
      end
    end

    it "correctly merges custom context with request context" do
      HTTP.get("http://localhost:3000/logs/custom", params: { append_info_to_payload: true })
      expect(logs.last).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/logs\/custom controller=LogsController action=custom hello=world current_time=\d+ status=204 duration=\d+\.\d+$/)
    end

    it "rebuilds log context for every log entry" do
      HTTP.get("http://localhost:3000/logs/custom")

      request_logs = logs.last(4)
      current_time_values = request_logs.map do |log|
        log.match(/current_time=(\d+)/)[1]
      end

      expect(current_time_values.uniq.size).to eq(4)
    end

    context "with cable connection" do
      it "enriches subscription logs" do
        with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
          expect(client).to be_connected
          expect(logs.last).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info current_time=\d+ message=client subscribed$/)
        end
      end

      it "enriches message logs" do
        with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
          expect(client).to be_connected
          client.send({ message: "test-message" }.to_json)

          websocket_logs = logs.last(2)

          expect(websocket_logs[0]).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info current_time=\d+ message=client subscribed$/)
          expect(websocket_logs[1]).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info content=test-message current_time=\d+ message=message received$/)
        end
      end

      it "rebuilds log context for every log entry" do
        with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
          expect(client).to be_connected
          client.send({ message: "test-message" }.to_json)

          websocket_logs = logs.last(2)
          current_time_values = websocket_logs.map do |log|
            log.match(/current_time=(\d+)/)[1]
          end

          expect(current_time_values.uniq.size).to eq(2)
        end
      end
    end
  end

  context "with invalid custom context" do
    before :all do
      launch_server(env: { "ENABLE_CUSTOM_INVALID_LOG_CONTEXT" => "1" })
    end

    after :all do
      stop_server
    end

    it "correctly handles exceptions when building log context" do
      response = HTTP.get("http://localhost:3000/get")
      expect(response.code).to eq(200)

      request_tag = logs.last.match(/^\[(\w{16})\]/)[1]
      request_logs = logs.select { |log| log.include?(request_tag) }

      expect(request_logs[0]).to match(/^\[#{request_tag}\] Unhandled exception when building log context: RuntimeError \(test\):$/)
      expect(request_logs[1]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/get controller=ApplicationController action=get status=200 duration=\d+\.\d+$/)
    end
  end

  context "with valid custom context and custom request ID" do
    before :all do
      launch_server(env: {
        "ENABLE_CUSTOM_LOG_CONTEXT" => "1",
        "ENABLE_REQUEST_ID_MIDDLEWARE" => "1"
      })
    end

    after :all do
      stop_server
    end

    it "uses internal request ID if X-Request-Id is not submitted" do
      HTTP.get("http://localhost:3000/logs/custom")

      request_logs = logs.last(4)
      request_logs.each do |log|
        expect(log).to match(/^\[\w{16}\]\[development\]/)
        expect(log).to match(/current_time=\d+/)
      end
    end

    it "uses the X-Request-Id value if it is submitted" do
      x_request_id = "my-test-request-id"
      HTTP.headers("X-Request-Id" => x_request_id).get("http://localhost:3000/logs/custom")

      request_logs = logs.last(4)
      request_logs.each do |log|
        expect(log).to match(/^\[#{x_request_id}\]\[development\]/)
        expect(log).to match(/current_time=\d+/)
      end
    end

    context "with cable connection" do
      it "uses internal request ID if X-Request-Id is not submitted" do
        with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
          expect(client).to be_connected
          client.send({ message: "test-message" }.to_json)

          websocket_logs = logs.last(2)
          websocket_logs.each do |log|
            expect(log).to match(/^\[\w{16}\]\[development\]/)
            expect(log).to match(/current_time=\d+/)
          end
        end
      end

      it "uses the X-Request-Id value if it is submitted" do
        x_request_id = "my-test-request-id"

        with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000", "X-Request-Id" => x_request_id }) do |client|
          expect(client).to be_connected
          client.send({ message: "test-message" }.to_json)

          websocket_logs = logs.last(2)
          websocket_logs.each do |log|
            expect(log).to match(/^\[#{x_request_id}\]\[development\]/)
            expect(log).to match(/current_time=\d+/)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "http"

RSpec.describe "Telemetry" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

  before :all do
    launch_server(env: { "ENABLE_TELEMETRY" => "1" })
  end

  after :all do
    stop_server
  end

  it "correctly processes telemetry handlers" do
    response = HTTP.get("http://localhost:3000/logs/custom")
    expect(response.code).to eq(204)

    request_tag = logs.last.match(/^\[(\w{16})\]/)[1]

    custom_logs = logs.select do |log|
      log.start_with?("[#{request_tag}][LogsController#custom]")
    end

    expect(custom_logs.size).to eq(3)
  end

  it "correctly processes exceptions" do
    response = HTTP.get("http://localhost:3000/raise_error")
    expect(response.code).to eq(500)
    expect(response.to_s).to start_with("RuntimeError (1155 test error)")

    telemetry_logs = logs.select do |log|
      log.include?("[ApplicationController#raise_error]") && log.include?("telemetry recorded exception 1155 test error")
    end

    expect(telemetry_logs.size).to eq(1)
  end
end

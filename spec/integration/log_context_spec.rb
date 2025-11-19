# frozen_string_literal: true

require "http"

RSpec.describe "Global log context" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

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

  it "correctly handles exceptions when building log context" do
    response = HTTP.headers("Raise-Log-Context-Exception" => "true").get("http://localhost:3000/get")
    expect(response.code).to eq(200)

    request_tag = logs.last.match(/^\[(\w{16})\]/)[1]
    request_logs = logs.select { |log| log.include?(request_tag) }

    expect(request_logs[0]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=error message=Unhandled exception when building log context: RuntimeError \(test\):$/)
    expect(request_logs[1]).to match(/^\[#{request_tag}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/get controller=ApplicationController action=get status=200 duration=\d+\.\d+$/)
  end

  it "correctly merges custom context with request context" do
    HTTP.get("http://localhost:3000/logs/custom", params: { append_info_to_payload: true })
    expect(logs.last).to match(/^\[\w{16}\]\[development\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/logs\/custom controller=LogsController action=custom current_time=\d+ hello=world status=204 duration=\d+\.\d+$/)
  end
end

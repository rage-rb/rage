# frozen_string_literal: true

require "http"

RSpec.describe "Custom Renderers" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

  before :all do
    launch_server(env: { "ENABLE_RENDERERS" => "1" })
  end

  after :all do
    stop_server
  end

  it "correctly processes plain renderers" do
    response = HTTP.get("http://localhost:3000/renderers/html")

    expect(response.code).to eq(200)
    expect(response.headers["content-type"]).to eq("text/html")
    expect(response.to_s.strip).to eq("<div>HTML content</div>")
  end

  it "correctly processes renderers with the status keyword" do
    response = HTTP.get("http://localhost:3000/renderers/erb")

    expect(response.code).to eq(202)
    expect(response.headers["content-type"]).to eq("text/html")
    expect(response.to_s.strip).to eq("<div>Hello, World</div>")
  end

  it "correctly processes renderers with custom keywords" do
    response = HTTP.persistent("http://localhost:3000").get("/renderers/erb_over_sse")

    expect(response.code).to eq(200)
    expect(response.headers["content-type"]).to include("text/event-stream")
    expect(response.to_s).to eq("data: <div>Hello, World</div>\n\n")
  end

  it "delegates to core renderers" do
    response = HTTP.get("http://localhost:3000/renderers/json")

    expect(response.code).to eq(201)
    expect(response.headers["content-type"]).to include("application/json")
    expect(response.parse).to eq({ "message" => "Hello, World" })
  end
end

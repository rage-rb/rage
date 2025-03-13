# frozen_string_literal: true

require "http"

RSpec.describe "Request ID" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

  context "without the RequestID middleware" do
    before :all do
      launch_server
    end

    after :all do
      stop_server
    end

    it "uses an internal request ID" do
      response = HTTP.get("http://localhost:3000/get_request_id")
      id = response.to_s

      expect(id.size).to eq(16)
      expect(logs.last).to start_with("[#{id}]")
      expect(response.headers["x-request-id"]).to be_nil
    end

    it "ignores the X-Request-Id header" do
      x_request_id = "my-test-request-id"
      response = HTTP.headers("X-Request-Id" => x_request_id).get("http://localhost:3000/get_request_id")

      expect(response.to_s).not_to eq(x_request_id)
      expect(response.headers["x-request-id"]).to be_nil
    end
  end

  context "with the RequestID middleware" do
    before :all do
      launch_server(env: { "ENABLE_REQUEST_ID_MIDDLEWARE" => "1" })
    end

    after :all do
      stop_server
    end

    it "uses an internal request ID if X-Request-Id is not submitted" do
      response = HTTP.get("http://localhost:3000/get_request_id")
      id = response.to_s

      expect(id.size).to eq(16)
      expect(logs.last).to start_with("[#{id}]")
      expect(response.headers["x-request-id"]).to eq(id)
    end

    it "uses the X-Request-Id value if it is submitted" do
      x_request_id = "my-test-request-id"
      response = HTTP.headers("X-Request-Id" => x_request_id).get("http://localhost:3000/get_request_id")

      expect(response.to_s).to eq(x_request_id)
      expect(logs.last).to start_with("[#{x_request_id}]")
      expect(response.headers["x-request-id"]).to eq(x_request_id)
    end
  end
end

# frozen_string_literal: true

RSpec.describe Rage::RequestId do
  subject { described_class.new(app).call(env)[1]["x-request-id"] }

  let(:app) { double }
  let(:response) { [200, {}, ["test response"]] }

  context "with no X-Request-Id header" do
    before do
      allow(app).to receive(:call) do |env|
        env["rage.request_id"] ||= "internal-request-id"
        response
      end
    end

    let(:env) { {} }

    it "returns the value of rage.request_id" do
      expect(subject).to eq("internal-request-id")
    end

    context "with empty value" do
      let(:env) { { "HTTP_X_REQUEST_ID" => "" } }

      it "returns the value of rage.request_id" do
        expect(subject).to eq("internal-request-id")
      end
    end
  end

  context "with X-Request-Id header" do
    before do
      allow(app).to receive(:call).with(env).and_return(response)
    end

    context "with standard value" do
      let(:env) { { "HTTP_X_REQUEST_ID" => "test-x-request-id" } }

      it "adds the ID to the env" do
        subject
        expect(env["rage.request_id"]).to eq("test-x-request-id")
      end

      it "adds the ID to the response" do
        subject
        expect(response[1]["x-request-id"]).to eq("test-x-request-id")
      end
    end

    context "with long value" do
      let(:env) { { "HTTP_X_REQUEST_ID" => "test" * 100 } }

      it "adds the truncated ID to the env" do
        subject
        expect(env["rage.request_id"].size).to eq(255)
      end

      it "adds the truncated ID to the response" do
        subject
        expect(response[1]["x-request-id"]).to eq(env["rage.request_id"])
      end
    end

    context "with invalid characters" do
      let(:env) { { "HTTP_X_REQUEST_ID" => "test x request id" } }

      it "adds the sanitized ID to the env" do
        subject
        expect(env["rage.request_id"]).to eq("testxrequestid")
      end

      it "adds the sanitized ID to the response" do
        subject
        expect(response[1]["x-request-id"]).to eq("testxrequestid")
      end
    end

    context "with both long value and invalid characters" do
      let(:env) { { "HTTP_X_REQUEST_ID" => "test+" * 100 } }

      it "adds the sanitized ID to the env" do
        subject
        expect(env["rage.request_id"].size).to be < 255
        expect(env["rage.request_id"]).not_to include("+")
      end

      it "adds the sanitized ID to the response" do
        subject
        expect(response[1]["x-request-id"]).to eq(env["rage.request_id"])
      end
    end
  end
end

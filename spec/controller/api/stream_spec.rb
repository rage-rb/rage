# frozen_string_literal: true

module ControllerApiStreamSpec
  class TestControllerStream < RageController::API
    def index
      render stream: "hello world".each_char
    end
  end

  class TestControllerStreamAnd204 < RageController::API
    def index
      render stream: "hello world".each_char, status: 204
    end
  end

  class TestControllerStreamAnd401 < RageController::API
    def index
      render stream: "hello world".each_char, status: 401
    end
  end

  class TestControllerTwoRenders < RageController::API
    def index
      render plain: "hello world"
      render stream: "hello world".each_char
    end
  end

  class TestControllerStreamAndPlain < RageController::API
    def index
      render stream: "hello world".each_char, plain: "hello world"
    end
  end

  class TestControllerStreamAndSSE < RageController::API
    def index
      render stream: "hello world".each_char, sse: "hello world"
    end
  end

  class TestControllerStreamAndCustomContentType < RageController::API
    def index
      headers["content-type"] = "application/x-ndjson"
      render stream: "hello world".each_char
    end
  end

  class TestControllerStreamAndInvalidBody < RageController::API
    def index
      render stream: proc { |s| s }
    end
  end
end

RSpec.describe RageController::API do
  let(:env) { {} }

  subject { run_action(klass, :index, env:) }

  context "with a streaming body" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStream }

    it "returns a streaming response" do
      status, headers, body = subject

      expect(status).to eq(200)
      expect(headers).to eq({ "content-type" => "text/plain; charset=utf-8" })
      expect(body).to be_a(Rage::Streaming)
    end
  end

  context "with 204 response status" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAnd204 }

    it "returns a regular head response" do
      status, _, body = subject

      expect(status).to eq(204)
      expect(body).to be_empty
      expect(body).not_to be_a(Rage::Streaming)
    end
  end

  context "with 401 response status" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAnd401 }

    it "raises an error" do
      expect { subject }.to raise_error(/Streaming responses only support 200 and 204 statuses/)
    end
  end

  context "with two renders" do
    let(:klass) { ControllerApiStreamSpec::TestControllerTwoRenders }

    it "raises an error" do
      expect { subject }.to raise_error(/Render was called multiple times/)
    end
  end

  context "with a standard body" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAndPlain }

    it "raises an error" do
      expect { subject }.to raise_error(/Cannot render both a standard body and an HTTP stream/)
    end
  end

  context "with an SSE stream" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAndSSE }

    it "raises an error" do
      expect { subject }.to raise_error(/Cannot render both an SSE stream and an HTTP stream/)
    end

    it "doesn't upgrade the request" do
      subject rescue nil
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with custom content type" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAndCustomContentType }

    it "preserves the custom content type" do
      _, headers, _ = subject
      expect(headers["content-type"]).to eq("application/x-ndjson")
    end
  end

  context "with a body that doesn't respond to #each" do
    let(:klass) { ControllerApiStreamSpec::TestControllerStreamAndInvalidBody }

    it "raises an error" do
      expect { subject }.to raise_error(ArgumentError, /must respond to #each/)
    end
  end
end

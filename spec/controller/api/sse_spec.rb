# frozen_string_literal: true

module ControllerApiSSESpec
  class TestControllerSSE < RageController::API
    def index
      render sse: "hello world"
    end
  end

  class TestControllerSSEAnd204 < RageController::API
    def index
      render sse: "hello world", status: 204
    end
  end

  class TestControllerSSEAnd401 < RageController::API
    def index
      render sse: "hello world", status: 401
    end
  end

  class TestControllerSSEAndNoContent < RageController::API
    def index
      render sse: "hello world", status: :no_content
    end
  end

  class TestControllerTwoRenders < RageController::API
    def index
      render plain: "hello world"
      render sse: "hello world"
    end
  end

  class TestControllerSSEAndPlain < RageController::API
    def index
      render sse: "hello world", plain: "hello world"
    end
  end

  class TestControllerSSEAndCustomContentType < RageController::API
    def index
      headers["content-type"] = "text/plain"
      render sse: "hello world"
    end
  end
end

RSpec.describe RageController::API do
  let(:env) { { "rack.upgrade?" => :sse } }

  subject { run_action(klass, :index, env:) }

  context "with SSE" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSE }

    it "returns an SSE response" do
      expect(subject).to match([0, { "content-type" => "text/event-stream" }, []])
    end

    it "upgrades the request" do
      subject
      expect(env["rack.upgrade"]).to be_a(Rage::SSE::Application)
    end
  end

  context "with 204 response status" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSEAnd204 }

    it "returns an SSE response" do
      status, headers, body = subject

      expect(status).to eq(204)
      expect(headers["content-type"]).not_to include("text/event-stream")
      expect(body).to be_empty
    end

    it "doesn't upgrade the request" do
      subject
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with 401 response status" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSEAnd401 }

    it "raises an error" do
      expect { subject }.to raise_error(/SSE responses only support 200 and 204 statuses/)
    end

    it "doesn't upgrade the request" do
      subject rescue nil
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with :no_content response status" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSEAndNoContent }

    it "returns an SSE response" do
      status, headers, body = subject

      expect(status).to eq(204)
      expect(headers["content-type"]).not_to include("text/event-stream")
      expect(body).to be_empty
    end

    it "doesn't upgrade the request" do
      subject
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with two renders" do
    let(:klass) { ControllerApiSSESpec::TestControllerTwoRenders }

    it "raises an error" do
      expect { subject }.to raise_error(/Render was called multiple times/)
    end

    it "doesn't upgrade the request" do
      subject rescue nil
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with double render" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSEAndPlain }

    it "raises an error" do
      expect { subject }.to raise_error(/Cannot render both a standard body and an SSE stream/)
    end

    it "doesn't upgrade the request" do
      subject rescue nil
      expect(env["rack.upgrade"]).to be_nil
    end
  end

  context "with custom content type" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSEAndCustomContentType }

    it "ensures correct content type" do
      _, headers, _ = subject
      expect(headers["content-type"]).to eq("text/event-stream")
    end
  end

  context "with a non-SSE request" do
    let(:klass) { ControllerApiSSESpec::TestControllerSSE }
    let(:env) { {} }

    it "returns an error" do
      status, headers, body = subject

      expect(status).to eq(406)
      expect(headers["content-type"]).not_to include("text/event-stream")
      expect(body[0]).to match(/Expected an SSE connection/)
    end

    it "doesn't upgrade the request" do
      subject
      expect(env["rack.upgrade"]).to be_nil
    end
  end
end

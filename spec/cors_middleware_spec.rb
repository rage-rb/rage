# frozen_string_literal: true

RSpec.describe Rage::Cors do
  subject { cors.call(env) }

  let(:env) { { "HTTP_ORIGIN" => "http://localhost:3000" } }
  let(:response) { [200, {}, ["test response"]] }
  let(:app) { double(call: response) }

  context "with all origins" do
    let(:cors) do
      described_class.new(app) do
        allow "*"
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*"
          },
          []
        ])
      end
    end
  end

  context "with mixed origins" do
    let(:cors) do
      described_class.new(app) do
        allow "*", "localhost:3000"
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000" }, ["test response"]])
    end
  end

  context "with matching origins" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3001", "localhost:3000"
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000", "Vary" => "Origin" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Vary" => "Origin"
          },
          []
        ])
      end
    end
  end

  context "with regexp origins" do
    let(:cors) do
      described_class.new(app) do
        allow /\w+\.mysite.com/
      end
    end

    let(:env) { { "HTTP_ORIGIN" => "http://subdomain3.mysite.com" } }

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://subdomain3.mysite.com", "Vary" => "Origin" }, ["test response"]])
    end

    context "with extra extension" do
      let(:env) { { "HTTP_ORIGIN" => "http://subdomain3.mysite.com.au" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://subdomain3.mysite.com.au", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with https" do
      let(:env) { { "HTTP_ORIGIN" => "https://subdomain3.mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "https://subdomain3.mysite.com", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with multiple subdomains" do
      let(:env) { { "HTTP_ORIGIN" => "http://new.subdomain3.mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://new.subdomain3.mysite.com", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with invalid extension" do
      let(:env) { { "HTTP_ORIGIN" => "http://subdomain3.mysite.co" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end
  end

  context "with regexp origin with protocol" do
    let(:cors) do
      described_class.new(app) do
        allow /\Ahttps:\/\/\w+\.mysite\.com\.au\z/
      end
    end

    context "with correct origin" do
      let(:env) { { "HTTP_ORIGIN" => "https://subdomain3.mysite.com.au" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "https://subdomain3.mysite.com.au", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with invalid extension" do
      let(:env) { { "HTTP_ORIGIN" => "https://subdomain3.mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end

    context "with extra extension" do
      let(:env) { { "HTTP_ORIGIN" => "https://subdomain3.mysite.com.au.ms" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end

    context "with invalid protocol" do
      let(:env) { { "HTTP_ORIGIN" => "http://subdomain3.mysite.com.au" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end

    context "without protocol" do
      let(:env) { { "HTTP_ORIGIN" => "subdomain3.mysite.com.au" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end
  end

  context "with custom protocol origins" do
    let(:cors) do
      described_class.new(app) do
        allow "chrome-extension://myextension"
      end
    end

    let(:env) { { "HTTP_ORIGIN" => "chrome-extension://myextension" } }

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "chrome-extension://myextension", "Vary" => "Origin" }, ["test response"]])
    end

    context "with invalid protocol" do
      let(:env) { { "HTTP_ORIGIN" => "https://myextension" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end
  end

  context "with specified protocols" do
    let(:cors) do
      described_class.new(app) do
        allow "https://mysite.com"
      end
    end

    let(:env) { { "HTTP_ORIGIN" => "https://mysite.com" } }

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "https://mysite.com", "Vary" => "Origin" }, ["test response"]])
    end

    context "with invalid protocol" do
      let(:env) { { "HTTP_ORIGIN" => "http://mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end
  end

  context "with default protocols" do
    let(:cors) do
      described_class.new(app) do
        allow "mysite.com"
      end
    end

    context "with https" do
      let(:env) { { "HTTP_ORIGIN" => "https://mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "https://mysite.com", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with http" do
      let(:env) { { "HTTP_ORIGIN" => "http://mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://mysite.com", "Vary" => "Origin" }, ["test response"]])
      end
    end

    context "with file" do
      let(:env) { { "HTTP_ORIGIN" => "file://mysite.com" } }

      it "sets correct headers" do
        expect(subject).to eq([200, {}, ["test response"]])
      end
    end
  end

  context "with invalid origin" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3001"
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, {}, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => ""
          },
          []
        ])
      end
    end
  end

  context "with no origin header" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3001"
      end
    end

    let(:env) { {} }

    it "sets correct headers" do
      expect(subject).to eq([200, {}, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => ""
          },
          []
        ])
      end
    end
  end

  context "with no origin header and all origins allowed" do
    let(:cors) do
      described_class.new(app) do
        allow "*"
      end
    end

    let(:env) { {} }

    it "sets correct headers" do
      expect(subject).to eq([200, {}, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => ""
          },
          []
        ])
      end
    end
  end

  context "with one allowed method" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000", methods: %i(get)
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000", "Vary" => "Origin" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "GET",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Vary" => "Origin"
          },
          []
        ])
      end
    end
  end

  context "with several allowed methods" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000", methods: %i(get head)
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000", "Vary" => "Origin" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Methods" => "GET, HEAD",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Vary" => "Origin"
          },
          []
        ])
      end
    end
  end

  context "with control headers" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000",
          methods: %i(get head),
          allow_headers: %w(X-Custom-Token),
          expose_headers: %w(X-Response-Header-1 X-Response-Header-2),
          max_age: 300
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([
        200,
        {
          "Access-Control-Allow-Origin" => "http://localhost:3000",
          "Access-Control-Expose-Headers" => "X-Response-Header-1, X-Response-Header-2",
          "Vary" => "Origin"
        },
        ["test response"]
      ])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Access-Control-Allow-Methods" => "GET, HEAD",
            "Access-Control-Allow-Headers" => "X-Custom-Token",
            "Access-Control-Expose-Headers" => "X-Response-Header-1, X-Response-Header-2",
            "Access-Control-Max-Age" => "300",
            "Vary" => "Origin"
          },
          []
        ])
      end
    end
  end

  context "with credentials" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000",
          methods: %i(get head),
          allow_headers: %w(X-Custom-Token),
          expose_headers: %w(X-Response-Header-1 X-Response-Header-2),
          max_age: 300,
          allow_credentials: true
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([
        200,
        {
          "Access-Control-Allow-Origin" => "http://localhost:3000",
          "Access-Control-Expose-Headers" => "X-Response-Header-1, X-Response-Header-2",
          "Access-Control-Allow-Credentials" => "true",
          "Vary" => "Origin"
        },
        ["test response"]
      ])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Access-Control-Allow-Methods" => "GET, HEAD",
            "Access-Control-Allow-Headers" => "X-Custom-Token",
            "Access-Control-Expose-Headers" => "X-Response-Header-1, X-Response-Header-2",
            "Access-Control-Max-Age" => "300",
            "Access-Control-Allow-Credentials" => "true",
            "Vary" => "Origin"
          },
          []
        ])
      end
    end
  end

  context "with credentials and wildcards" do
    let(:cors) do
      described_class.new(app) do
        allow "*",
          methods: "*",
          allow_headers: %w(Content-Type),
          allow_credentials: true
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000", "Access-Control-Allow-Credentials" => "true" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Access-Control-Allow-Methods" => "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
            "Access-Control-Allow-Headers" => "Content-Type",
            "Access-Control-Allow-Credentials" => "true"
          },
          []
        ])
      end
    end
  end

  context "with wildcards and no credentials" do
    let(:cors) do
      described_class.new(app) do
        allow "*",
          methods: "*",
          allow_headers: "*",
          expose_headers: "*"
      end
    end

    it "sets correct headers" do
      expect(subject).to eq([200, { "Access-Control-Allow-Origin" => "http://localhost:3000", "Access-Control-Expose-Headers" => "*" }, ["test response"]])
    end

    context "with preflight requests" do
      let(:env) { super().merge("REQUEST_METHOD" => "OPTIONS") }

      it "sets correct headers" do
        expect(subject).to eq([
          204,
          {
            "Access-Control-Allow-Origin" => "http://localhost:3000",
            "Access-Control-Allow-Methods" => "*",
            "Access-Control-Allow-Headers" => "*",
            "Access-Control-Expose-Headers" => "*"
          },
          []
        ])
      end
    end
  end

  context "with credentials and allow_headers as wildcard" do
    let(:cors) do
      described_class.new(app) do
        allow "*", allow_headers: "*", allow_credentials: true
      end
    end

    it "raises an error" do
      expect { cors }.to raise_error(/explicitly list allowed headers/)
    end
  end

  context "with credentials and expose_headers as wildcard" do
    let(:cors) do
      described_class.new(app) do
        allow "*", allow_headers: %w(Content-Type), expose_headers: "*", allow_credentials: true
      end
    end

    it "raises an error" do
      expect { cors }.to raise_error(/explicitly list exposed headers/)
    end
  end

  context "with invalid methods" do
    let(:cors) do
      described_class.new(app) do
        allow "*", methods: %w(DELET)
      end
    end

    it "raises an error" do
      expect { cors }.to raise_error("Unsupported method passed to Rage::Cors: DELET")
    end
  end

  context "with Vary header in response" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000"
      end
    end

    let(:response) { [200, { "Vary" => "Authorization" }, ["test response"]] }

    it "sets correct headers" do
      expect(subject).to eq([
        200,
        {
          "Vary" => "Authorization, Origin",
          "Access-Control-Allow-Origin" => "http://localhost:3000"
        },
        ["test response"]
      ])
    end
  end

  context "with exception" do
    let(:cors) do
      described_class.new(app) do
        allow "localhost:3000"
      end
    end

    before do
      allow(app).to receive(:call).and_raise("test error")
    end

    it "correctly processes exceptions" do
      expect { subject }.to raise_error(RuntimeError, "test error")
    end
  end
end

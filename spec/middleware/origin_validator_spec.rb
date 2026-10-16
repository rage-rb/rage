# frozen_string_literal: true

RSpec.describe Rage::OriginValidator do
  subject { validator.call(env) }

  let(:env) { { "HTTP_ORIGIN" => origin, "HTTP_HOST" => host } }
  let(:origin) { "http://localhost:3000" }
  let(:host) { "localhost:3000" }
  let(:response) { [200, {}, ["test response"]] }
  let(:app) { double(call: response) }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:error)
  end

  describe "default behavior (allow_same_origin_as_host: true)" do
    let(:validator) { described_class.new(app) }

    context "when origin matches host with http" do
      let(:origin) { "http://localhost:3000" }
      let(:host) { "localhost:3000" }

      it "allows the request" do
        expect(subject).to eq(response)
      end

      it "calls the app" do
        subject
        expect(app).to have_received(:call).with(env)
      end
    end

    context "when origin matches host with https" do
      let(:origin) { "https://example.com" }
      let(:host) { "example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches host with port" do
      let(:origin) { "https://example.com:8443" }
      let(:host) { "example.com:8443" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin does not match host" do
      let(:origin) { "http://attacker.com" }
      let(:host) { "localhost:3000" }

      it "rejects the request with 404" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end

      it "does not call the app" do
        subject
        expect(app).not_to have_received(:call)
      end

      it "logs an error" do
        subject
        expect(logger).to have_received(:error).with("Request origin not allowed: http://attacker.com")
      end
    end

    context "when origin has different protocol than expected" do
      let(:origin) { "http://example.com" }
      let(:host) { "example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin is a subdomain of host" do
      let(:origin) { "http://sub.localhost:3000" }
      let(:host) { "localhost:3000" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when host is a suffix of origin but not matching" do
      let(:origin) { "http://evilocalhost:3000" }
      let(:host) { "localhost:3000" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when origin has no protocol prefix" do
      let(:origin) { "localhost:3000" }
      let(:host) { "localhost:3000" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "with allow_same_origin_as_host: false" do
    context "with no allowed origins" do
      let(:validator) { described_class.new(app, allow_same_origin_as_host: false) }

      it "rejects all requests" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end

      it "logs an error" do
        subject
        expect(logger).to have_received(:error).with("Request origin not allowed: http://localhost:3000")
      end
    end

    context "with explicit allowed origins" do
      let(:validator) { described_class.new(app, "http://allowed.com", allow_same_origin_as_host: false) }

      context "when origin matches allowed origin" do
        let(:origin) { "http://allowed.com" }

        it "allows the request" do
          expect(subject).to eq(response)
        end
      end

      context "when origin does not match allowed origin" do
        let(:origin) { "http://notallowed.com" }

        it "rejects the request" do
          expect(subject).to eq([404, {}, ["Not Found"]])
        end
      end

      context "when origin matches host but same-origin is disabled" do
        let(:origin) { "http://localhost:3000" }
        let(:host) { "localhost:3000" }

        it "rejects the request" do
          expect(subject).to eq([404, {}, ["Not Found"]])
        end
      end
    end
  end

  describe "with explicit string origins" do
    let(:validator) { described_class.new(app, "http://allowed.com", "https://secure.com") }

    context "when origin matches first allowed origin" do
      let(:origin) { "http://allowed.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches second allowed origin" do
      let(:origin) { "https://secure.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin does not match any allowed origin" do
      let(:origin) { "http://unknown.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when origin matches host (same-origin enabled by default)" do
      let(:origin) { "http://localhost:3000" }
      let(:host) { "localhost:3000" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end
  end

  describe "with regex origins" do
    let(:validator) { described_class.new(app, /\.example\.com\z/) }

    context "when origin matches regex" do
      let(:origin) { "http://sub.example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches regex with different subdomain" do
      let(:origin) { "https://api.example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin does not match regex" do
      let(:origin) { "http://example.org" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when origin partially matches but not at end" do
      let(:origin) { "http://example.com.attacker.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "with mixed string and regex origins" do
    let(:validator) { described_class.new(app, "http://exact.com", /\.wildcard\.com\z/) }

    context "when origin matches exact string" do
      let(:origin) { "http://exact.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches regex" do
      let(:origin) { "https://sub.wildcard.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches neither" do
      let(:origin) { "http://other.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "with multiple regex origins" do
    let(:validator) { described_class.new(app, /dev\.example\.com\z/, /prod\.example\.com\z/) }

    context "when origin matches first regex" do
      let(:origin) { "http://dev.example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches second regex" do
      let(:origin) { "https://prod.example.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches neither regex" do
      let(:origin) { "http://staging.example.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "edge cases" do
    context "with nil origin" do
      let(:validator) { described_class.new(app) }
      let(:env) { { "HTTP_HOST" => host } }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "with nil origin and explicit allowed origins" do
      let(:validator) { described_class.new(app, "http://allowed.com") }
      let(:env) { { "HTTP_HOST" => host } }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "with nil host" do
      let(:validator) { described_class.new(app) }
      let(:env) { { "HTTP_ORIGIN" => origin } }

      it "rejects the request when same-origin check cannot be performed" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "with nil host but matching explicit origin" do
      let(:validator) { described_class.new(app, "http://localhost:3000") }
      let(:env) { { "HTTP_ORIGIN" => "http://localhost:3000" } }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "with both nil origin and nil host" do
      let(:validator) { described_class.new(app) }
      let(:env) { {} }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "with empty origin" do
      let(:validator) { described_class.new(app) }
      let(:origin) { "" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "with origin containing special characters" do
      let(:validator) { described_class.new(app, "http://example.com/path?query=1") }
      let(:origin) { "http://example.com/path?query=1" }

      it "allows exact match" do
        expect(subject).to eq(response)
      end
    end

    context "with regex containing special regex characters" do
      let(:validator) { described_class.new(app, /example\.com/) }

      context "when origin matches escaped dot" do
        let(:origin) { "http://example.com" }

        it "allows the request" do
          expect(subject).to eq(response)
        end
      end

      context "when origin has different character instead of dot" do
        let(:origin) { "http://exampleXcom" }

        it "rejects the request" do
          expect(subject).to eq([404, {}, ["Not Found"]])
        end
      end
    end
  end

  describe "same-origin validation details" do
    let(:validator) { described_class.new(app) }

    context "with http origin" do
      let(:origin) { "http://myapp.com" }
      let(:host) { "myapp.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "with https origin" do
      let(:origin) { "https://myapp.com" }
      let(:host) { "myapp.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when size matches but host doesn't" do
      let(:origin) { "http://evil.com" }
      let(:host) { "good.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when host is prefix of different host" do
      let(:origin) { "http://myapp.com.evil.com" }
      let(:host) { "myapp.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end

    context "when host is a suffix of origin and has similar length" do
      let(:origin) { "https://example.com" }
      let(:host) { "http://xexample.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "combining same-origin with explicit origins" do
    let(:validator) { described_class.new(app, "http://api.external.com") }

    context "when origin matches host" do
      let(:origin) { "http://localhost:3000" }
      let(:host) { "localhost:3000" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches explicit origin" do
      let(:origin) { "http://api.external.com" }

      it "allows the request" do
        expect(subject).to eq(response)
      end
    end

    context "when origin matches neither" do
      let(:origin) { "http://unknown.com" }

      it "rejects the request" do
        expect(subject).to eq([404, {}, ["Not Found"]])
      end
    end
  end

  describe "response passthrough" do
    let(:validator) { described_class.new(app, origin) }
    let(:response) { [201, { "Content-Type" => "application/json" }, ["{\"id\": 1}"]] }

    it "passes through the full response from the app" do
      expect(subject).to eq(response)
    end
  end
end

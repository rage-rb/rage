RSpec.describe Rage::Request do
  let(:env) do
    {
      "rack.upgrade?" => nil,
      "rack.upgrade" => nil,
      "rack.version" => [1, 3],
      "rage.request_id" => "5zfcwiy09bary01l",
      "SCRIPT_NAME" => "",
      "rack.url_scheme" => "http",
      "HTTP_VERSION" => "HTTP/1.1",
      "PATH_INFO" => "/users",
      "QUERY_STRING" => "show_archived=true",
      "REMOTE_ADDR" => "::1",
      "REQUEST_METHOD" => "GET",
      "SERVER_NAME" => "localhost",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "IODINE_REQUEST_ID" => "QUERY_STRING",
      "IODINE_HAS_BODY" => false,
      "SERVER_PORT" => "3000",
      "HTTP_HOST" => "localhost:3000",
      "HTTP_CONNECTION" => "keep-alive",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; ...",
      "HTTP_ACCEPT" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
      "HTTP_ACCEPT_ENCODING" => "gzip, deflate, br, zstd",
      "HTTP_ACCEPT_LANGUAGE" => "en-GB,en-US;q=0.9,en;q=0.8",
      "HTTP_COOKIE" => "test_cookie=1",
      "HTTP_X_FORWARDED_FOR" => "127.0.0.1",
      "CONTENT_TYPE" => "application/json"
    }
  end

  subject(:request) { described_class.new(env) }

  it "returns the full URL" do
    expect(request.url).to eq("http://localhost:3000/users?show_archived=true")
  end

  it "returns the path" do
    expect(request.path).to eq("/users")
  end

  it "returns the full path with query string" do
    expect(request.fullpath).to eq("/users?show_archived=true")
  end

  it "returns the user agent" do
    expect(request.user_agent).to eq("Mozilla/5.0 (Macintosh; ...")
  end

  context "when SERVER_PORT is a default port" do
    before do
      env["rack.url_scheme"] = "http"
      env["SERVER_PORT"] = "80"
      env["HTTP_HOST"] = "localhost:80"
    end

    it "it omits HTTP port 80 in the URL" do
      expect(request.url).to eq("http://localhost/users?show_archived=true")
    end

    context "and using HTTPS" do
      before do
        env["rack.url_scheme"] = "https"
        env["SERVER_PORT"] = "443"
        env["HTTP_HOST"] = "localhost:443"
      end

      it "omits the HTTPS port 443 in the URL" do
        expect(request.url).to eq("https://localhost/users?show_archived=true")
      end
    end
  end

  describe "QUERY_STRING property" do
    context "when QUERY_STRING is empty" do
      before do
        env["QUERY_STRING"] = ""
      end

      it "returns the path without query string" do
        expect(request.fullpath).to eq("/users")
      end
    end
    context "when QUERY_STRING is not empty" do
      it "handles the query string property of a request" do
        expect(request.query_string).to eq("show_archived=true")
      end
    end
  end

  context "when HTTP_USER_AGENT is missing" do
    before do
      env.delete("HTTP_USER_AGENT")
    end

    it "returns nil for user_agent" do
      expect(request.user_agent).to be_nil
    end
  end

  describe "host property of a request" do
    subject { request.host }

    context "with HTTP_HOST header" do
      context "when host contains port" do
        it { is_expected.to eq("localhost") } # uses default env
      end

      context "when host is without port" do
        before { env["HTTP_HOST"] = "localhost" }
        it { is_expected.to eq("localhost") }
      end

      context "when using IP address with port" do
        before { env["HTTP_HOST"] = "127.0.0.1:8080" }
        it { is_expected.to eq("127.0.0.1") }
      end

      context "when containing subdomains" do
        before { env["HTTP_HOST"] = "api.foo.bar.com:443" }
        it { is_expected.to eq("api.foo.bar.com") }
      end
    end

    context "without HTTP_HOST header" do
      before do
        env.delete("HTTP_HOST")
        env["SERVER_NAME"] = "fallback.example"
        env["SERVER_PORT"] = "3000"
      end

      it "falls back to SERVER_NAME" do
        expect(subject).to eq("fallback.example")
      end
    end
  end

  describe "domain property" do
    context "with default HTTP_HOST" do
      it "returns the correct domain" do
        expect(request.domain).to eq("localhost")
        expect(request.domain(0)).to eq("localhost")
        expect(request.domain(2)).to eq("localhost")
      end
    end

    context "with HTTP_HOST set to tld0.tld1.tld2" do
      before { env["HTTP_HOST"] = "tld0.tld1.tld2" }

      it "returns the correct domains for different levels" do
        expect(request.domain(0)).to eq("tld2")
        expect(request.domain(1)).to eq("tld1.tld2")
        expect(request.domain(2)).to eq("tld0.tld1.tld2")
        expect(request.domain(3)).to eq("tld0.tld1.tld2")
      end
    end
  end

  describe "HTTP method handling" do
    context "with GET request" do
      it "identifies GET method" do
        expect(request.method).to eq("GET") # default init is GET
        expect(request.get?).to eq(true)
      end
    end

    context "with POST request" do
      before do
        env["REQUEST_METHOD"] = "POST"
      end

      it "identifies POST method" do
        expect(request.method).to eq("POST")
        expect(request.post?).to eq(true)
      end
    end
    context "with PATCH request" do
      before do
        env["REQUEST_METHOD"] = "PATCH"
      end
      it "identifies PATCH method" do
        expect(request.method).to eq("PATCH")
        expect(request.patch?).to eq(true)
      end
    end
    context "with PUT request" do
      before do
        env["REQUEST_METHOD"] = "PUT"
      end

      it "identifies PUT method" do
        expect(request.method).to eq("PUT")
        expect(request.put?).to eq(true)
      end
    end
    context "with DELETE request" do
      before do
        env["REQUEST_METHOD"] = "DELETE"
      end

      it "identifies DELETE method" do
        expect(request.method).to eq("DELETE")
        expect(request.delete?).to eq(true)
      end
    end

    context "with HEAD request" do
      before do
        env["REQUEST_METHOD"] = "HEAD"
      end
      it "identifies HEAD method" do
        expect(request.method).to eq("HEAD")
        expect(request.head?).to eq(true)
      end
    end
  end

  it "handles the port property of a request" do
    expect(request.port).to eq(3000)
  end

  describe "protocol property of a request" do
    context "with HTTP" do
      it "returns 'http://'" do
        expect(request.protocol).to eq("http://")
      end
    end

    context "with HTTPS" do
      before do
        env["rack.url_scheme"] = "https"
        env["SERVER_PORT"] = "443"
      end
      it "returns 'https://'" do
        expect(request.protocol).to eq("https://")
      end
    end
  end

  it "handles the env property of a request" do
    expect(request.env).to eq(env)
  end

  it "handles the format property of a request" do
    expect(request.format).to eq("application/json")
  end

  it "returns the correct request ID" do
    expect(request.request_id).to eq("5zfcwiy09bary01l")
  end

  it "returns the correct request ID" do
    expect(request.request_id).to eq("5zfcwiy09bary01l")
  end

  context "#route_uri_pattern" do
    context "with no controller passed" do
      it "returns the request path" do
        expect(request.route_uri_pattern).to eq("/users")
      end
    end

    context "with controller passed" do
      subject(:request) { described_class.new(env, controller:) }

      let(:controller) { double }

      it "calls Rage::Router::Util" do
        expect(controller).to receive(:class).and_return("test-class")
        expect(controller).to receive(:action_name).and_return("test-action")

        expect(Rage::Router::Util).to receive(:route_uri_pattern).
          with("test-class", "test-action").
          and_return("test-uri-pattern")

        expect(request.route_uri_pattern).to eq("test-uri-pattern")
      end
    end
  end
end

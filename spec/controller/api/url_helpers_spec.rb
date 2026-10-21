# frozen_string_literal: true

RSpec.describe RageController::API do
  let(:klass) { Class.new(RageController::API) }

  let(:routes) do
    [
      {
        method: "GET",
        path: "/users",
        params: [],
        meta: { controller: "users", action: "index" }
      },
      {
        method: "GET",
        path: "/users/:id",
        params: ["id"],
        meta: { controller: "users", action: "show" }
      },
      {
        method: "GET",
        path: "/posts",
        params: [],
        meta: { controller: "posts", action: "index" }
      }
    ]
  end

  before do
    allow(Rage.__router).to receive(:routes).and_return(routes)
    Rage::Router::Util.class_variable_set(:@@path_builders, Hash.new { |h, k| h[k] = {} })
  end

  describe "#url_for" do
    it "generates a full URL using request host and protocol" do
      env = { "rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443" }
      url = klass.new(env, nil).url_for(controller: "users", action: "index")

      expect(url).to eq("https://example.com/users")
    end

    it "generates a URL with path params" do
      env = { "rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "80" }
      url = klass.new(env, nil).url_for(controller: "users", action: "show", id: 123)

      expect(url).to eq("http://example.com/users/123")
    end

    it "allows overriding host and protocol" do
      env = { "rack.url_scheme" => "http", "HTTP_HOST" => "default.host", "SERVER_PORT" => "80" }
      url = klass.new(env, nil).url_for(controller: "users", action: "show", id: 456, host: "custom.host", protocol: "https")

      expect(url).to eq("https://custom.host/users/456")
    end

    it "generates a URL for a different controller" do
      env = { "rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443" }
      url = klass.new(env, nil).url_for(controller: "posts", action: "index")

      expect(url).to eq("https://example.com/posts")
    end

    context "with only_path: true" do
      it "returns only the path" do
        env = { "rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443" }
        url = klass.new(env, nil).url_for(controller: "users", action: "show", id: 789, only_path: true)

        expect(url).to eq("/users/789")
      end
    end

    context "with non-standard port" do
      it "includes the port in the URL" do
        env = { "rack.url_scheme" => "http", "HTTP_HOST" => "localhost", "SERVER_PORT" => "80" }
        url = klass.new(env, nil).url_for(controller: "users", action: "show", id: 111, port: 3000)

        expect(url).to eq("http://localhost:3000/users/111")
      end

      it "includes request port when non-standard" do
        env = { "rack.url_scheme" => "http", "HTTP_HOST" => "localhost:3000" }
        url = klass.new(env, nil).url_for(controller: "users", action: "index")

        expect(url).to eq("http://localhost:3000/users")
      end
    end

    context "with standard port" do
      it "omits port 80 for http" do
        env = { "rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "80" }
        url = klass.new(env, nil).url_for(controller: "users", action: "index")

        expect(url).to eq("http://example.com/users")
      end

      it "omits port 443 for https" do
        env = { "rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443" }
        url = klass.new(env, nil).url_for(controller: "users", action: "index")

        expect(url).to eq("https://example.com/users")
      end
    end
  end
end

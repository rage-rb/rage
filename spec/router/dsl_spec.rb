# frozen_string_literal: true

RSpec.describe Rage::Router::DSL do
  let(:router) { instance_double("Rage::Router::Backend") }
  let(:dsl) { described_class.new(router) }

  it "correctly adds get handlers" do
    expect(router).to receive(:on).with("GET", "/test", "test#index", a_hash_including(constraints: {}))
    dsl.draw { get("/test", to: "test#index") }
  end

  it "correctly adds post handlers" do
    expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(constraints: {}))
    dsl.draw { post("/test", to: "test#index") }
  end

  it "correctly adds put handlers" do
    expect(router).to receive(:on).with("PUT", "/test", "test#index", a_hash_including(constraints: {}))
    dsl.draw { put("/test", to: "test#index") }
  end

  it "correctly adds patch handlers" do
    expect(router).to receive(:on).with("PATCH", "/test", "test#index", a_hash_including(constraints: {}))
    dsl.draw { patch("/test", to: "test#index") }
  end

  it "correctly adds delete handlers" do
    expect(router).to receive(:on).with("DELETE", "/test", "test#index", a_hash_including(constraints: {}))
    dsl.draw { delete("/test", to: "test#index") }
  end

  it "correctly adds root handlers" do
    expect(router).to receive(:on).with("GET", "/", "test#index", a_hash_including(constraints: {}))
    dsl.draw { root(to: "test#index") }
  end

  context "with constraints" do
    it "correctly adds post handlers" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(constraints: { host: "test.com" }))
      dsl.draw { post("/test", to: "test#index", constraints: { host: "test.com" }) }
    end

    it "correctly adds put handlers" do
      expect(router).to receive(:on).with("PUT", "/test", "test#index", a_hash_including(constraints: { host: /test/ }))
      dsl.draw { put("/test", to: "test#index", constraints: { host: /test/ }) }
    end
  end

  context "with path scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PUT", "/api/v1/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw do
        scope(path: "api/v1") { put("/test", to: "test#index") }
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PATCH", "/api/v1/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw do
        scope(path: "/api/v1/") { patch("/test", to: "test#index") }
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("DELETE", "/api/v1/*", "test#index", a_hash_including(constraints: {}))
      dsl.draw do
        scope(path: "/api/v1/") { delete("*", to: "test#index") }
      end
    end
  end

  context "with module scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("POST", "/test", "api/test#index", a_hash_including(constraints: {}))
      dsl.draw do
        scope(module: "api") { post("/test", to: "test#index") }
      end
    end
  end

  context "with path and module scopes" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("GET", "/api/test", "api/test#index", a_hash_including(constraints: {}))
      expect(router).to receive(:on).with("POST", "/api/v1/test", "api/v1/test#index", a_hash_including(constraints: {}))
      expect(router).to receive(:on).with("PUT", "/api/v2/internal/test", "api/test#index", a_hash_including(constraints: {}))

      dsl.draw do
        scope module: "api", path: "api" do
          get "/test", to: "test#index"

          scope path: "/v1" do
            scope module: "v1" do
              post "test", to: "test#index"
            end
          end

          scope path: "v2/internal/" do
            put "test", to: "test#index"
          end
        end
      end
    end

    it "raises an error in case of incorrect options" do
      expect {
        dsl.draw do
          scope as: "new_path" do
            get "/test", to: "test#index"
          end
        end
      }.to raise_error("only 'module' and 'path' options are accepted")
    end
  end

  context "with root helper inside a scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("GET", "/api/v1/internal", "api/test#index", a_hash_including(constraints: {}))

      dsl.draw do
        scope path: "api/v1" do
          scope path: "internal", module: "api" do
            root to: "test#index"
          end
        end
      end
    end
  end

  context "with default options" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("DELETE", "/test", "test#index", a_hash_including(defaults: { id: "5", format: "png" }))
      dsl.draw { delete("/test", to: "test#index", defaults: { id: "5", format: "png" }) }
    end
  end

  context "with the default handler" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PATCH", "/test", "test#index", a_hash_including(defaults: { id: "5", format: "png" }))

      dsl.draw do
        defaults id: "5", format: "png" do
          patch "/test", to: "test#index"
        end
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", a_hash_including(defaults: { id: "5", format: "svg" }))

      dsl.draw do
        defaults id: "5" do
          get "/test", to: "test#index", defaults: { format: "svg" }
        end
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(defaults: { id: "6" }))

      dsl.draw do
        defaults id: "5" do
          post "/test", to: "test#index", defaults: { id: "6" }
        end
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PATCH", "/test1", "test#index", a_hash_including(defaults: { version: "v1", format: "webp" }))
      expect(router).to receive(:on).with("DELETE", "/test2", "test#index", a_hash_including(defaults: { version: "v1", format: "webp", id: "-1" }))
      expect(router).to receive(:on).with("GET", "/test3", "test#index", a_hash_including(defaults: { version: "v1" }))
      expect(router).to receive(:on).with("POST", "/test4", "test#index", a_hash_including(defaults: { version: "v2" }))

      dsl.draw do
        defaults version: "v1" do
          defaults format: "webp" do
            patch "/test1", to: "test#index"
            delete "/test2", to: "test#index", defaults: { id: "-1" }
          end

          get "/test3", to: "test#index"

          defaults version: "v2" do
            post "/test4", to: "test#index"
          end
        end
      end
    end
  end

  context "with the match helper" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        match "/test", to: "test#index", via: [:get, :post]
      end
    end

    it "correctly adds handlers on via: :all" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PUT", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PATCH", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("DELETE", "/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        match "/test", to: "test#index", via: :all
      end
    end

    it "correctly routes to all when no via is specified" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PUT", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PATCH", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("DELETE", "/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        match "/test", to: "test#index"
      end
    end
  end
end

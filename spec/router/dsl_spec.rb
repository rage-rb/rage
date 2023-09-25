# frozen_string_literal: true

RSpec.describe Rage::Router::DSL do
  let(:router) { instance_double("Rage::Router::Backend") }
  let(:dsl) { described_class.new(router) }

  it "correctly adds get handlers" do
    expect(router).to receive(:on).with("GET", "/test", "test#index", { constraints: {} })
    dsl.draw { get("/test", to: "test#index") }
  end

  it "correctly adds post handlers" do
    expect(router).to receive(:on).with("POST", "/test", "test#index", { constraints: {} })
    dsl.draw { post("/test", to: "test#index") }
  end

  it "correctly adds put handlers" do
    expect(router).to receive(:on).with("PUT", "/test", "test#index", { constraints: {} })
    dsl.draw { put("/test", to: "test#index") }
  end

  it "correctly adds patch handlers" do
    expect(router).to receive(:on).with("PATCH", "/test", "test#index", { constraints: {} })
    dsl.draw { patch("/test", to: "test#index") }
  end

  it "correctly adds delete handlers" do
    expect(router).to receive(:on).with("DELETE", "/test", "test#index", { constraints: {} })
    dsl.draw { delete("/test", to: "test#index") }
  end

  it "correctly adds root handlers" do
    expect(router).to receive(:on).with("GET", "/", "test#index", { constraints: {} })
    dsl.draw { root(to: "test#index") }
  end

  context "with constraints" do
    it "correctly adds post handlers" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", { constraints: { host: "test.com" } })
      dsl.draw { post("/test", to: "test#index", constraints: { host: "test.com" }) }
    end

    it "correctly adds put handlers" do
      expect(router).to receive(:on).with("PUT", "/test", "test#index", { constraints: { host: /test/ } })
      dsl.draw { put("/test", to: "test#index", constraints: { host: /test/ }) }
    end
  end

  context "with path scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PUT", "/api/v1/test", "test#index", { constraints: {} })
      dsl.draw do
        scope(path: "api/v1") { put("/test", to: "test#index") }
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("PATCH", "/api/v1/test", "test#index", { constraints: {} })
      dsl.draw do
        scope(path: "/api/v1/") { patch("/test", to: "test#index") }
      end
    end

    it "correctly adds handlers" do
      expect(router).to receive(:on).with("DELETE", "/api/v1/*", "test#index", { constraints: {} })
      dsl.draw do
        scope(path: "/api/v1/") { delete("*", to: "test#index") }
      end
    end
  end

  context "with module scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("POST", "/test", "api/test#index", { constraints: {} })
      dsl.draw do
        scope(module: "api") { post("/test", to: "test#index") }
      end
    end
  end

  context "with path and module scopes" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("GET", "/api/test", "api/test#index", { constraints: {} })
      expect(router).to receive(:on).with("POST", "/api/v1/test", "api/v1/test#index", { constraints: {} })
      expect(router).to receive(:on).with("PUT", "/api/v2/internal/test", "api/test#index", { constraints: {} })

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
      expect(router).to receive(:on).with("GET", "/api/v1/internal", "api/test#index", { constraints: {} })

      dsl.draw do
        scope path: "api/v1" do
          scope path: "internal", module: "api" do
            root to: "test#index"
          end
        end
      end
    end
  end
end

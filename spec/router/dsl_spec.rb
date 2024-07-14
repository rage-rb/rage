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

  it "doesn't allow routes with no handler" do
    expect {
      dsl.draw { get("test") }
    }.to raise_error("Missing :to key on routes definition, please check your routes.")
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
      }.to raise_error("only :module, :path, and :controller options are accepted")
    end
  end

  context "with controller scope" do
    it "correctly adds handlers" do
      expect(router).to receive(:on).with("POST", "/api/v1/like", "api/v1/photos#like", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/api/v1/dislike", "api/v1/photos#dislike", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/api/v1/index", "api/v1/all_photos#index", instance_of(Hash))

      dsl.draw do
        namespace "api/v1" do
          scope controller: "photos" do
            post "like"
            post "dislike"
          end

          controller "all_photos" do
            get "index"
          end
        end
      end
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
      expect(router).to receive(:on).with("HEAD", "/test", "test#index", constraints: {}, defaults: nil)
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
      expect(router).to receive(:on).with("HEAD", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("GET", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PUT", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PATCH", "/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("DELETE", "/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        match "/test", to: "test#index"
      end
    end

    it "correctly adds defaults and constraints" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", constraints: { host: "test.com" }, defaults: { id: "5" })
      expect(router).to receive(:on).with("POST", "/test", "test#index", constraints: { host: "test.com" }, defaults: { id: "5" })

      dsl.draw do
        match "/test", to: "test#index", via: [:get, :post], constraints: { host: "test.com" }, defaults: { id: "5" }
      end
    end

    it "correctly routes via get with scope" do
      expect(router).to receive(:on).with("GET", "/api/v1/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        scope path: "api/v1" do
          match "/test", to: "test#index", via: :get
        end
      end
    end

    it "correctly routes via get with scope and module" do
      expect(router).to receive(:on).with("GET", "/api/v1/test", "api/test#index", constraints: {}, defaults: nil)

      dsl.draw do
        scope path: "api/v1", module: "api" do
          match "/test", to: "test#index", via: :get
        end
      end
    end

    it "correctly routes via all with scope" do
      expect(router).to receive(:on).with("HEAD", "/api/v1/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("GET", "/api/v1/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/api/v1/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PUT", "/api/v1/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PATCH", "/api/v1/test", "test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("DELETE", "/api/v1/test", "test#index", constraints: {}, defaults: nil)

      dsl.draw do
        scope path: "api/v1" do
          match "/test", to: "test#index", via: :all
        end
      end
    end

    it "uses namespace helper" do
      expect(router).to receive(:on).with("HEAD", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("GET", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("POST", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PUT", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("PATCH", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)
      expect(router).to receive(:on).with("DELETE", "/api/v1/test", "api/v1/test#index", constraints: {}, defaults: nil)

      dsl.draw do
        namespace "api" do
          namespace "v1" do
            match "/test", to: "test#index", via: :all
          end
        end
      end
    end

    it "uses resources method" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", defaults: nil, constraints: {})
      dsl.draw do
        get "/photos", to: "photos#index"
      end
    end

    it "uses get under namespace" do
      expect(router).to receive(:on).with("GET", "/api/v1/photos", "api/v1/photos#index", defaults: nil, constraints: {})

      dsl.draw do
        namespace "api" do
          namespace "v1" do
            get "/photos", to: "photos#index"
          end
        end
      end
    end

    it "uses get under namespace with path" do
      expect(router).to receive(:on).with("GET", "/api/v2/photos", "api/v1/photos#index", defaults: nil, constraints: {})

      dsl.draw do
        namespace "api/v1", path: "api/v2" do
          get "/photos", to: "photos#index"
        end
      end
    end

    it "uses get under namespace with path and module" do
      expect(router).to receive(:on).with("GET", "/api/v2/photos", "api/v2/photos#index", defaults: nil, constraints: {})

      dsl.draw do
        namespace "api/v1", path: "api/v2", module: "api/v2" do
          get "/photos", to: "photos#index"
        end
      end
    end
  end

  context "with the mount helper" do
    let(:default_http_methods) { %w(GET POST PUT PATCH DELETE HEAD) }

    before do
      stub_const("TestRackApp", ->(env) { [200, { "Content-Type" => "text/plain" }, ["Hello, Rack!"]] })
    end

    context "with keyword arguments" do
      it "correctly mounts Rack applications" do
        expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
        dsl.draw { mount(TestRackApp, at: "/test_route") }
      end

      it "allows to customize http methods" do
        expect(router).to receive(:mount).with("/test_route", TestRackApp, %w(POST PUT))
        dsl.draw { mount(TestRackApp, at: "/test_route", via: %i(post put)) }
      end
    end

    context "with hash arguments" do
      it "correctly mounts Rack applications" do
        expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
        dsl.draw { mount(TestRackApp => "/test_route") }
      end

      it "allows to customize http methods" do
        expect(router).to receive(:mount).with("/test_route", TestRackApp, %w(DELETE))
        dsl.draw { mount(TestRackApp => "/test_route", via: :delete) }
      end
    end

    it "correctly processes via: :all options" do
      expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
      dsl.draw { mount(TestRackApp, at: "/test_route", via: :all) }
    end

    it "validates http methods" do
      expect {
        dsl.draw { mount(TestRackApp, at: "/test_route", via: %i(all get)) }
      }.to raise_error(/Invalid HTTP method: all/)
    end

    it "adds leading slashes" do
      expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
      dsl.draw { mount(TestRackApp, at: "test_route") }
    end

    it "removes trailing slashes" do
      expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
      dsl.draw { mount(TestRackApp, at: "/test_route/") }
    end

    context "with a class" do
      before do
        klass = Class.new do
          def call(env)
            [200, { "Content-Type" => "text/plain" }, ["Hello, Rack!"]]
          end
        end
        stub_const("TestRackApp", klass)
      end

      it "correctly mounts Rack applications" do
        expect(router).to receive(:mount).with("/test_route", TestRackApp, default_http_methods)
        dsl.draw { mount(TestRackApp => "/test_route") }
      end
    end
  end

  context "with resources" do
    it "correctly creates routes" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos
      end
    end

    it "correctly creates routes under module" do
      expect(router).to receive(:on).with("GET", "/photos", "api/photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "api/photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:id", "api/photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:id", "api/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:id", "api/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "api/photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, module: "api"
      end
    end

    it "correctly creates routes under path" do
      expect(router).to receive(:on).with("GET", "/api/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/api/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/api/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/api/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/api/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/api/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, path: "api/photos"
      end
    end

    it "correctly creates routes under module and path" do
      expect(router).to receive(:on).with("GET", "/my_photos", "v1/photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/my_photos", "v1/photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/my_photos/:id", "v1/photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/my_photos/:id", "v1/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/my_photos/:id", "v1/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/my_photos/:id", "v1/photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, path: "my_photos", module: "v1"
      end
    end

    it "correctly creates routes with the :except option" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, except: :show
      end
    end

    it "correctly creates routes with the :only option" do
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, only: %i(create destroy)
      end
    end

    it "ignores non-standard actions" do
      expect(router).not_to receive(:on)

      dsl.draw do
        resources :photos, only: %i(my_action)
      end
    end

    it "correctly creates routes with the :param option" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:slug", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:slug", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:slug", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:slug", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, param: "slug"
      end
    end

    it "raises in case the :param option has incorrect value" do
      expect {
        dsl.draw do
          resources :photos, param: ":slug"
        end
      }.to raise_error(":param option can't contain colons")
    end

    it "correctly works with :param as a symbol" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:slug", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:slug", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:slug", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:slug", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :photos, param: :slug
      end
    end

    it "correctly creates routes with multiple options" do
      expect(router).to receive(:on).with("GET", "/api/v1/photos", "api/photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/api/v1/photos", "api/photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/api/v1/photos/:slug", "api/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/api/v1/photos/:slug", "api/photos#update", instance_of(Hash))

      dsl.draw do
        resources :photos, module: "api", path: "api/v1/photos", param: "slug", only: %i(index create update)
      end
    end

    it "correctly creates nested routes" do
      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "photos#destroy", instance_of(Hash))

      expect(router).to receive(:on).with("POST", "/photos/:photo_id/like", "likes#create", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:photo_id/dislike", "photos#dislike", instance_of(Hash))

      dsl.draw do
        resources :photos do
          post "/like", to: "likes#create"
          delete :dislike
        end
      end
    end

    it "correctly creates nested routes with options" do
      expect(router).to receive(:on).with("GET", "/my_photos", "api/photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/my_photos/:slug", "api/photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/my_photos/:slug", "api/photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/my_photos/:slug", "api/photos#update", instance_of(Hash))

      expect(router).to receive(:on).with("POST", "/my_photos/:photo_slug/like", "api/likes#create", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/my_photos/:photo_slug/dislike", "api/photos#dislike", instance_of(Hash))

      dsl.draw do
        resources :photos, module: "api", path: "/my_photos/", param: "slug", except: %i(create destroy like) do
          post "/like", to: "likes#create"
          patch :dislike
        end
      end
    end

    it "correctly creates nested routes on collection" do
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos/like_all", "photos#like_all", instance_of(Hash))

      dsl.draw do
        resources :photos, only: :show do
          collection do
            post :like_all
          end
        end
      end
    end

    it "correctly creates nested routes on collection with the :on option" do
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos/like_all", "photos#like_all", instance_of(Hash))

      dsl.draw do
        resources :photos, only: :show do
          post :like_all, on: :collection
        end
      end
    end

    it "correctly creates nested routes on member" do
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos/:id/like", "photos#like", instance_of(Hash))

      dsl.draw do
        resources :photos, only: :show do
          member do
            post :like
          end
        end
      end
    end

    it "correctly creates nested routes on member with the :on option" do
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos/:id/like", "photos#like", instance_of(Hash))

      dsl.draw do
        resources :photos, only: :show do
          post :like, on: :member
        end
      end
    end

    it "correctly creates nested routes on member with a custom param" do
      expect(router).to receive(:on).with("POST", "/photos/:photo_uuid/like", "photos#like", instance_of(Hash))

      dsl.draw do
        resources :photos, only: [], param: :photo_uuid do
          member do
            post :like
          end
        end
      end
    end

    it "correctly creates nested resources" do
      expect(router).to receive(:on).with("GET", "/albums", "albums#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/albums", "albums#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/albums/:id", "albums#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/albums/:id", "albums#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/albums/:id", "albums#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/albums/:id", "albums#destroy", instance_of(Hash))

      expect(router).to receive(:on).with("GET", "/albums/:album_id/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/albums/:album_id/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/albums/:album_id/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/albums/:album_id/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/albums/:album_id/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/albums/:album_id/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :albums do
          resources :photos
        end
      end
    end

    it "correctly creates nested resources with options" do
      expect(router).to receive(:on).with("POST", "/albums", "albums#create", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/albums/:slug", "albums#destroy", instance_of(Hash))

      expect(router).to receive(:on).with("GET", "/albums/:album_slug/my_photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/albums/:album_slug/my_photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/albums/:album_slug/my_photos/:id", "photos#destroy", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/albums/:album_slug/my_photos/:photo_id/add_to_album", "photos#add_to_album", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/albums/:album_slug/my_photos/like_all", "photo_likes#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/albums/:album_slug/my_photos/:id/keywords", "photos#keywords", instance_of(Hash))

      expect(router).to receive(:on).with("POST", "/albums/sort", "albums#sort", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/albums/:album_slug/tag", "albums#tag", instance_of(Hash))

      dsl.draw do
        resources :albums, only: %i(create destroy), param: "slug" do
          resources :photos, except: %i(create update), path: "my_photos" do
            post :add_to_album

            collection do
              post "like_all", to: "photo_likes#create"
            end

            member do
              get :keywords
            end
          end

          collection do
            post :sort
          end

          patch :tag
        end
      end
    end

    it "correctly creates multiple routes at the same time" do
      expect(router).to receive(:on).with("GET", "/albums", "albums#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/albums", "albums#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/albums/:id", "albums#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/albums/:id", "albums#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/albums/:id", "albums#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/albums/:id", "albums#destroy", instance_of(Hash))

      expect(router).to receive(:on).with("GET", "/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/photos/:id", "photos#destroy", instance_of(Hash))

      dsl.draw do
        resources :albums, :photos
      end
    end

    it "correctly passes options to multiple routes at the same time" do
      expect(router).to receive(:on).with("POST", "/albums", "admin/albums#create", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/photos", "admin/photos#create", instance_of(Hash))

      expect(router).to receive(:on).with("PUT", "/albums/:album_id/tag", "admin/albums#tag", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/photos/:photo_id/tag", "admin/photos#tag", instance_of(Hash))

      dsl.draw do
        resources :albums, :photos, only: :create, module: :admin do
          put :tag
        end
      end
    end

    it "correctly creates routes with the `scope` helper" do
      expect(router).to receive(:on).with("GET", "/:album_id/photos", "photos#index", instance_of(Hash))
      expect(router).to receive(:on).with("POST", "/:album_id/photos", "photos#create", instance_of(Hash))
      expect(router).to receive(:on).with("GET", "/:album_id/photos/:id", "photos#show", instance_of(Hash))
      expect(router).to receive(:on).with("PATCH", "/:album_id/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("PUT", "/:album_id/photos/:id", "photos#update", instance_of(Hash))
      expect(router).to receive(:on).with("DELETE", "/:album_id/photos/:id", "photos#destroy", instance_of(Hash))

      expect(router).to receive(:on).with("POST", "/:album_id/photos/:photo_id/like", "photos#like", instance_of(Hash))

      dsl.draw do
        scope path: ":album_id" do
          resources :photos do
            post :like
          end
        end
      end
    end

    it "doesn't create routes" do
      expect(router).not_to receive(:on)

      dsl.draw do
        resources :photos, only: []
      end
    end

    it "uses activesupport" do
      allow_any_instance_of(String).to receive(:singularize).and_return("image")

      expect(router).to receive(:on).with("POST", "/photos/:image_id/mark", "photos#mark", instance_of(Hash))

      dsl.draw do
        resources :photos, only: [] do
          post :mark
        end
      end
    end
  end

  context "with legacy url helpers" do
    it "correctly adds get handlers" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { get("/test" => "test#index") }
    end

    it "correctly adds post handlers" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { post("/test" => "test#index") }
    end

    it "correctly adds put handlers" do
      expect(router).to receive(:on).with("PUT", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { put("/test" => "test#index") }
    end

    it "correctly adds patch handlers" do
      expect(router).to receive(:on).with("PATCH", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { patch("/test" => "test#index") }
    end

    it "correctly adds delete handlers" do
      expect(router).to receive(:on).with("DELETE", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { delete("/test" => "test#index") }
    end

    it "correctly adds constraints" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(constraints: { host: "test.com" }))
      dsl.draw { post("/test" => "test#index", constraints: { host: "test.com" }) }
    end

    it "correctly adds constraints and defaults" do
      expect(router).to receive(:on).with("POST", "/test", "test#index", a_hash_including(constraints: { host: "test.com" }, defaults: { id: "5", format: "png" }))
      dsl.draw { post("/test" => "test#index", constraints: { host: "test.com" }, defaults: { id: "5", format: "png" }) }
    end

    it "correctly adds namespaced handlers" do
      expect(router).to receive(:on).with("PUT", "/api/v1/test", "api/v1/test#index", a_hash_including(constraints: {}))

      dsl.draw do
        namespace "api/v1" do
          put "test" => "test#index"
        end
      end
    end

    context "with implicit controller" do
      it "correctly adds handlers" do
        expect(router).to receive(:on).with("GET", "/test", "users#index", a_hash_including(constraints: {}))

        dsl.draw do
          controller :users do
            get "test" => :index
          end
        end
      end

      it "fails if no controller can be found" do
        expect { dsl.draw { get("test" => :index) } }.to raise_error(/Could not derive/)
      end
    end

    context "with implicit action" do
      it "correctly adds handlers" do
        expect(router).to receive(:on).with("PATCH", "/test", "users#test", a_hash_including(constraints: {}))
        dsl.draw { patch "test" => "users" }
      end

      it "rewrites previously set controller values" do
        expect(router).to receive(:on).with("POST", "/test", "users#test", a_hash_including(constraints: {}))

        dsl.draw do
          controller :photos do
            post "test" => "users"
          end
        end
      end

      it "uses the last section of the path as the action value" do
        expect(router).to receive(:on).with("GET", "/api/users/all", "test#all", a_hash_including(constraints: {}))
        dsl.draw { get "api/users/all" => "test" }
      end

      it "correctly adds scoped handlers" do
        expect(router).to receive(:on).with("GET", "/api/users/all", "test#all", a_hash_including(constraints: {}))

        dsl.draw do
          scope path: "api/users" do
            get "all" => "test"
          end
        end
      end
    end
  end

  context "with legacy root helper" do
    it "correctly adds root handlers" do
      expect(router).to receive(:on).with("GET", "/", "test#index", a_hash_including(constraints: {}))
      dsl.draw { root("test#index") }
    end

    it "correctly adds namespaced handlers" do
      expect(router).to receive(:on).with("GET", "/api/v1", "api/v1/test#index", a_hash_including(constraints: {}))

      dsl.draw do
        namespace "api/v1" do
          root "test#index"
        end
      end
    end
  end

  context "with the `as` option" do
    it "correctly adds get handlers" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { get("/test", to: "test#index", as: :test_123) }
    end

    it "correctly adds legacy get handlers" do
      expect(router).to receive(:on).with("GET", "/test", "test#index", a_hash_including(constraints: {}))
      dsl.draw { get("/test" => "test#index", as: :test_123) }
    end
  end
end

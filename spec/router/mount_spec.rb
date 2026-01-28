RSpec.describe Rage::Router::Backend do
  it "correctly mounts a Rack app" do
    router.mount("/rack_app", ->(_) { :rack_app_response }, %w(GET HEAD))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_head_request("/rack_app")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_head_request("/rack_app/index")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_post_request("/rack_app")
    expect(result).to be_nil
  end

  it "updates script name" do
    router.mount("/rack_app", ->(env) { env["SCRIPT_NAME"] }, %w(GET))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq("/rack_app")

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq("/rack_app")
  end

  it "updates path info" do
    router.mount("/rack_app", ->(env) { env["PATH_INFO"] }, %w(GET))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq("/")

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq("/index")

    result, _ = perform_get_request("/rack_app/get/all/")
    expect(result).to eq("/get/all")
  end

  it "validates the handler" do
    expect {
      router.mount("/rack_app", 5, %w(GET))
    }.to raise_error(/should respond to `call`/)
  end

  context "with session" do
    let(:app) do
      Class.new do
        def self.name
          "Sidekiq::Web"
        end

        def self.call(env)
        end
      end
    end

    context "with Rack::Session available" do
      let(:session) do
        Class.new do
          def initialize(app, **)
            @app = app
          end

          def call(env)
            :test_session
          end
        end
      end

      before do
        allow(Rage).to receive(:config).and_return(double(secret_key_base: "test secret"))
        stub_const("Rack::Session::Cookie", session)
      end

      it "exposes session object" do
        router.mount("/test", app, %w(GET))

        response, _ = perform_get_request("/test")
        expect(response).to eq(:test_session)
      end

      it "rewinds request body" do
        router.mount("/test", app, %w(GET))

        body = StringIO.new("test body").tap(&:read)
        perform_get_request("/test", body:)

        expect(body.read).to eq("test body")
      end
    end

    context "with Rack::Session unavailable" do
      it "raises exception" do
        expect {
          router.mount("/test", app, %w(GET))
        }.to raise_error(/`Sidekiq::Web` depends on `Rack::Session`/)
      end
    end
  end
end

module RspecHelpersSpec
  class TestController < RageController::API
    def index
      render json: %w(test_1 test_2 test_3)
    end

    def params_action
      render plain: params[:i]
    end

    def headers_action
      if request.headers["Content-Type"] == "text/plain" &&
        request.headers["Cache-Control"] == "max-age=604800, must-revalidate" &&
        request.headers["Last-Modified"] == "Sun, 03 Sep 2017 00:17:02 GMT"
        head :ok
      else
        head :bad_request
      end
    end

    def fibers_action
      i = Fiber.await([
        Fiber.schedule { 10 },
        Fiber.schedule { 11 },
      ])

      render plain: i.sum
    end

    def subdomain
      head :ok
    end

    def logger
      VeryImportantService.new.call
      head :ok
    end
  end

  Rage.routes.draw do
    root to: "rspec_helpers_spec/test#index"

    get "params", to: "rspec_helpers_spec/test#params_action"
    post "params", to: "rspec_helpers_spec/test#params_action"

    get "headers", to: "rspec_helpers_spec/test#headers_action"
    get "fibers", to: "rspec_helpers_spec/test#fibers_action"

    get "subdomain", to: "rspec_helpers_spec/test#subdomain", constraints: { host: /rage-test/ }
    get "logger", to: "rspec_helpers_spec/test#logger"
  end

  class VeryImportantService
    def call
      Rage.logger.tagged("test") do
        Rage.logger.with_context(test_key: true) do
          Rage.logger.info "test"
        end
      end

      true
    end
  end
end

RSpec.describe "RSpec helpers", type: :request do
  before do
    allow(Rage).to receive(:root).and_return(Pathname.new(__dir__).expand_path)
    require "rage/rspec"
  end

  it "correctly parses responses" do
    get "/"

    expect(response.body).to eq('["test_1","test_2","test_3"]')
    expect(response.parsed_body).to eq(%w(test_1 test_2 test_3))
  end

  it "correctly matches http statuses" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response).to have_http_status(200)

    expect {
      expect(response).to have_http_status(:missing)
    }.to raise_error("expected the response to have a missing status code (404) but it was 200")

    expect {
      expect(response).to have_http_status(500)
    }.to raise_error("expected the response to have status code 500 but it was 200")

    expect {
      expect(response).not_to have_http_status(:success)
    }.to raise_error("expected the response not to have a success status code (2xx) but it was 200")
  end

  it "correctly passes params" do
    get "/params?i=222"
    expect(response.body).to eq("222")

    post "/params?i=333"
    expect(response.body).to eq("333")

    post "/params", params: { i: "444" }
    expect(response.body).to eq("444")

    post "/params", params: { i: "555" }, as: :json
    expect(response.body).to eq("555")
  end

  it "works correctly with no params" do
    post "/params"
    expect(response.body).to eq("")
  end

  it "correctly passes headers" do
    get "/headers", headers: {
      "content-type" => "text/plain",
      "Cache-Control" => "max-age=604800, must-revalidate",
      "HTTP_LAST_MODIFIED" => "Sun, 03 Sep 2017 00:17:02 GMT"
    }

    expect(response).to have_http_status(:ok)
  end

  it "allows to correctly schedule fibers" do
    get "/fibers"
    expect(response.body).to eq("21")
  end

  it "uses the default host value" do
    get "/subdomain"
    expect(response).to have_http_status(:not_found)
  end

  it "allows to modify host value" do
    host! "rage-test.com"
    get "/subdomain"

    expect(response).to have_http_status(:ok)
  end

  it "allows to stub app calls" do
    allow_any_instance_of(RageController::API).to receive(:params).and_return({ i: "12345" })

    get "/params?i=111"
    expect(response.body).to eq("12345")
  end

  it "allows to add custom logs" do
    get "/logger"
    expect(response).to have_http_status(:ok)
  end

  it "allows to add custom logs outside the request scope" do
    expect(RspecHelpersSpec::VeryImportantService.new.call).to be(true)
  end
end

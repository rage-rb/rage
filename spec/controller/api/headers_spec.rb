# frozen_string_literal: true

module ControllerApiHeadersSpec
  class TestController < RageController::API
    def index
      headers["custom_header_1"] = "1"
      headers.merge!("custom_header_2" => "22")

      render json: "hello", status: :created
    end

    def show
      head :ok
    end

    def create
      headers["custom_header_1"] = "111"
      render plain: "hello"
    end
  end
end

RSpec.describe RageController::API do
  let(:klass) { ControllerApiHeadersSpec::TestController }

  it "correctly sets headers" do
    status, headers, body = run_action(klass, :index)

    expect(status).to eq(201)
    expect(headers).to include("content-type" => "application/json; charset=utf-8", "custom_header_1" => "1", "custom_header_2" => "22")
    expect(body).to eq(["hello"])
  end

  it "doesn't overwrite default headers" do
    _, headers, _ = run_action(klass, :show)
    expect(headers).not_to include("custom_header_1" => "1", "custom_header_2" => "22")
  end

  it "doesn't overwrite previously set headers" do
    _, headers, _ = run_action(klass, :create)
    expect(headers).to include("custom_header_1" => "111", "content-type" => "text/plain; charset=utf-8")
  end
end

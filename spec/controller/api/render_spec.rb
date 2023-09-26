# frozen_string_literal: true

module ControllerApiRenderSpec
  class TestController < RageController::API
    def render_json
      render json: { message: "hello world" }
    end

    def head_symbol
      head :created
    end

    def head_int
      head 402
    end

    def render_json_with_status
      render json: { message: "hello world" }, status: :created
    end

    def render_plain_with_status
      render plain: "hi", status: 304
    end

    def render_plain_with_object
      render plain: %w(hi)
    end

    def render_status
      render status: 202
    end
  end
end

RSpec.describe RageController::API do
  let(:klass) { ControllerApiRenderSpec::TestController }
  let(:json_header) { { "content-type" => "application/json; charset=utf-8" } }

  it "correctly renders json" do
    expect(run_action(klass, :render_json)).to eq([200, json_header, ["{\"message\":\"hello world\"}"]])
  end

  it "correctly heads a symbol status" do
    expect(run_action(klass, :head_symbol)).to eq([201, json_header, []])
  end

  it "correctly heads an integer status" do
    expect(run_action(klass, :head_int)).to eq([402, json_header, []])
  end

  it "correctly renders json with status" do
    expect(run_action(klass, :render_json_with_status)).to eq([201, json_header, ["{\"message\":\"hello world\"}"]])
  end

  it "correctly renders text with status" do
    expect(run_action(klass, :render_plain_with_status)).to eq([304, { "content-type" => "text/plain; charset=utf-8" }, ["hi"]])
  end

  it "converts objects to string when rendering text" do
    expect(run_action(klass, :render_plain_with_object)).to eq([200, { "content-type" => "text/plain; charset=utf-8" }, [%w(hi).to_s]])
  end

  it "correctly renders status" do
    expect(run_action(klass, :render_status)).to eq([202, json_header, []])
  end
end

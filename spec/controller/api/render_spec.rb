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

    def render_status
      render status: 202
    end
  end
end

RSpec.describe RageController::API do
  let(:klass) { ControllerApiRenderSpec::TestController }

  it "correctly renders json" do
    expect(run_action(klass, :render_json)).to eq([200, {}, ["{\"message\":\"hello world\"}"]])
  end

  it "correctly heads a symbol status" do
    expect(run_action(klass, :head_symbol)).to eq([201, {}, []])
  end

  it "correctly heads an integer status" do
    expect(run_action(klass, :head_int)).to eq([402, {}, []])
  end

  it "correctly renders json with status" do
    expect(run_action(klass, :render_json_with_status)).to eq([201, {}, ["{\"message\":\"hello world\"}"]])
  end

  it "correctly renders text with status" do
    expect(run_action(klass, :render_plain_with_status)).to eq([304, {}, ["hi"]])
  end

  it "correctly renders status" do
    expect(run_action(klass, :render_status)).to eq([202, {}, []])
  end
end

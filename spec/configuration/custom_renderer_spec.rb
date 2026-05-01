# frozen_string_literal: true

require "securerandom"

module ConfigurationCustomRendererSpec
  class BaseController < RageController::API
  end
end

RSpec.describe Rage::Configuration do
  describe "#renderer / custom renderers" do
    let(:config) { described_class.new }

    def build_controller(&block)
      klass = Class.new(ConfigurationCustomRendererSpec::BaseController)
      klass.class_eval(&block) if block
      klass
    end

    it "registers a renderer and overloads `render` on RageController::API after finalize" do
      config.renderer(:csv) do |object, delimiter: ","|
        headers["content-type"] = "text/csv"
        object.join(delimiter)
      end

      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render csv: %w[a b c], delimiter: ";"
        end
      end

      expect(run_action(controller, :index)).to eq(
        [200, { "content-type" => "text/csv" }, ["a;b;c"]]
      )
    end

    it "supports status: on overloaded `render` method" do
      config.renderer(:csv) do |object|
        headers["content-type"] = "text/csv"
        object.join(",")
      end

      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render csv: %w[a b], status: :created
        end
      end

      expect(run_action(controller, :index)).to eq(
        [201, { "content-type" => "text/csv" }, ["a,b"]]
      )
    end

    it "raises when renderer is registered without a block" do
      expect { config.renderer(:csv) }.to raise_error(ArgumentError)
    end

    it "raises on duplicate renderer names" do
      config.renderer(:csv) { "x" }

      expect {
        config.renderer(:csv) { "y" }
      }.to raise_error(ArgumentError)
    end

    it "executes renderer in controller context (can access headers/request/params)" do
      config.renderer(:ctx) do |_|
        headers["content-type"] = "text/plain; charset=utf-8"
        "id=#{params[:id]}"
      end

      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render ctx: true
        end
      end

      expect(run_action(controller, :index, params: { id: 42 })).to eq(
        [200, { "content-type" => "text/plain; charset=utf-8" }, ["id=42"]]
      )
    end

    it "converts nil return value to empty string body" do
      config.renderer(:empty) do |_|
        headers["content-type"] = "text/plain; charset=utf-8"
        nil
      end

      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render empty: true
        end
      end

      expect(run_action(controller, :index)).to eq(
        [200, { "content-type" => "text/plain; charset=utf-8" }, [""]]
      )
    end

    it "does not double-render when renderer block calls render internally" do
      config.renderer(:sse_like) do |_|
        render plain: "from-inner-render", status: :accepted
      end

      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render sse_like: true
        end
      end

      status, _headers, body = run_action(controller, :index)
      expect(status).to eq(202)
      expect(body).to eq(["from-inner-render"])
    end

    it "raises if custom renderer is called after already rendering in action" do
      config.renderer(:csv) { |_obj| "x" }
      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render plain: "first"
          render csv: %w[a b]
        end
      end

      expect { run_action(controller, :index) }.to raise_error(/Render was called multiple times in this action/)
    end

    it "allows to set multiple renderers" do
      config.renderer(:csv) { |_| "csv content" }
      config.renderer(:erb) { |_| "erb content" }
      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render csv: true
        end

        define_method(:show) do
          render erb: true
        end
      end

      expect(run_action(controller, :index)).to match([200, instance_of(Hash), ["csv content"]])
      expect(run_action(controller, :show)).to match([200, instance_of(Hash), ["erb content"]])
    end

    it "raises if multiple custom renderer are called together" do
      config.renderer(:csv) { |_| "csv" }
      config.renderer(:erb) { |_| "erb" }
      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render csv: true, erb: true
        end
      end

      expect { run_action(controller, :index) }.to raise_error(Rage::Errors::AmbiguousRenderError)
    end

    it "delegates to the original `render`" do
      config.renderer(:csv) { |_| "csv" }
      config.__finalize

      controller = build_controller do
        define_method(:index) do
          render json: { message: "test" }, status: 202
        end
      end

      expect(run_action(controller, :index)).to match(
        [202, { "content-type" => "application/json; charset=utf-8" }, ["{\"message\":\"test\"}"]]
      )
    end
  end
end

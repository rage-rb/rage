# frozen_string_literal: true

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
  
      it "registers a renderer and defines render_<name> on RageController::API after finalize" do
        config.renderer(:csv) do |object, delimiter: ","|
          headers["content-type"] = "text/csv"
          object.join(delimiter)
        end
  
        config.__finalize
  
        controller = build_controller do
          def index
            render_csv %w[a b c], delimiter: ";"
          end
        end
  
        expect(run_action(controller, :index)).to eq(
          [200, { "content-type" => "text/csv" }, ["a;b;c"]]
        )
      end
  
      it "supports status: on generated render_<name> method" do
        config.renderer(:csv) do |object|
          headers["content-type"] = "text/csv"
          object.join(",")
        end
  
        config.__finalize
  
        controller = build_controller do
          def index
            render_csv %w[a b], status: :created
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
  
      it "raises when generated method conflicts with existing API method" do
        name = :conflict_renderer
        method_name = :"render_#{name}"
      
        # create a real method so the conflict is real
        RageController::API.define_method(method_name) {}
      
        config.renderer(name) { "x" }
      
        expect {
          config.__finalize
        }.to raise_error(ArgumentError, /#{Regexp.escape(method_name.to_s)}/)
      ensure
        RageController::API.send(:remove_method, method_name) if RageController::API.method_defined?(method_name)
      end
  
      it "executes renderer in controller context (can access headers/request/params)" do
        config.renderer(:ctx) do |_|
          headers["content-type"] = "text/plain; charset=utf-8"
          "id=#{params[:id]}"
        end
  
        config.__finalize
  
        controller = build_controller do
          def index
            render_ctx nil
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
          def index
            render_empty nil
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
          def index
            render_sse_like nil
          end
        end
  
        expect(run_action(controller, :index)).to eq(
          [202, { "content-type" => "text/plain; charset=utf-8" }, ["from-inner-render"]]
        )
      end
  
      it "raises if custom renderer is called after already rendering in action" do
        config.renderer(:csv) { |_obj| "x" }
        config.__finalize
  
        controller = build_controller do
          def index
            render plain: "first"
            render_csv %w[a b]
          end
        end
  
        expect { run_action(controller, :index) }
          .to raise_error("Render was called multiple times in this action")
      end
    end
  end
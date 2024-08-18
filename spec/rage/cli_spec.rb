require "rage/cli"

RSpec.describe Rage::CLI do
  subject(:rage_cli) { described_class.new }

  describe "#middleware" do
    let(:config_ru) { "spec/rspec/config.ru" }

    before do
      allow(rage_cli).to receive(:options).and_return(config: config_ru)
      allow(Rack::Builder).to receive(:parse_file).with(config_ru).and_return([app])
    end

    context "when middleware stack is present" do
      let(:app) do
        Rack::Builder.app do
          use Rage::FiberWrapper
          use Rage::Reloader
          run ->(env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
        end
      end

      it "lists the middleware stack" do
        expect { rage_cli.middleware }.to output(/Rage::FiberWrapper\nRage::Reloader/).to_stdout
      end
    end

    context "when middleware stack is empty" do
      let(:app) { ->(env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] } }

      it "does not list any middleware" do
        expect { rage_cli.middleware }.to output("").to_stdout
      end
    end
  end

  describe "#version" do
    before do
      stub_const("Rage::VERSION", "1.0.0")
    end

    it "returns the current version of the framework" do
      expect { rage_cli.version }.to output("1.0.0\n").to_stdout
    end
  end
end

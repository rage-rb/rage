require "rage/cli"

RSpec.describe Rage::CLI do
  subject(:rage_cli) { described_class.new }

  describe "#middleware" do
    before do
      allow(rage_cli).to receive(:environment)
      allow(Rage.config).to receive_message_chain(:middleware, :middlewares).and_return(middlewares)
    end

    context "when middleware stack is present" do
      let(:middlewares) { [[Rage::FiberWrapper], [Rage::Reloader, [], nil]] }

      it "lists the middleware stack" do
        expect { rage_cli.middleware }.to output("use \Rage::FiberWrapper\nuse \Rage::Reloader\n").to_stdout
      end
    end

    context "when middleware stack is empty" do
      let(:middlewares) { [] }

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

  describe "#console" do
    require "irb"

    let(:fiber_scheduler) do
      instance_double("Rage::FiberScheduler", block: true, unblock: true, kernel_sleep: true, io_wait: true)
    end

    before do
      allow(Rage::FiberScheduler).to receive(:new).and_return(fiber_scheduler)
      allow(rage_cli).to receive(:environment).and_return(true)
      allow(IRB).to receive(:start).and_return(true)
    end

    it "setups FiberScheduler before running console" do
      expect(Fiber).to receive(:set_scheduler).with(fiber_scheduler)

      rage_cli.console
    end
  end
end

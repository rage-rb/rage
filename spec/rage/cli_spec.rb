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
    context "when Fiber is monkey patched" do
      before do
        # Save the original methods to revert them before a test.
        # The patch_fiber_for_irb method affects the Fiber class between tests.
        Fiber.singleton_class.class_eval do
          alias_method :original_schedule_backup, :schedule
          alias_method :original_await_backup, :await
        end

        require "irb"
        allow(rage_cli).to receive(:environment)
        allow(IRB).to receive(:start)
        rage_cli.console
      end

      after do
        # Revert the original Fiber methods and drop backups after a test.
        Fiber.singleton_class.class_eval do
          alias_method :schedule, :original_schedule_backup
          alias_method :await, :original_await_backup
          remove_method :original_schedule_backup
          remove_method :original_await_backup
        end
      end

      it "Fiber.schedule and Fiber.await work during the rage console (binding.irb)" do
        expect {
          Fiber.schedule { :test }
          Fiber.await(Fiber.schedule { :test })
        }.not_to raise_error
      end

      it "executes Fibers in strict sequential order" do
        execution_order = []

        Fiber.schedule { execution_order << 1 }
        Fiber.schedule { execution_order << 2 }
        Fiber.schedule { execution_order << 3 }

        expect(execution_order).to eq([1, 2, 3])
      end
    end

    context "when Fiber is not monkey patched" do
      before do
        require "irb"
        allow(rage_cli).to receive(:patch_fiber_for_irb)
        allow(rage_cli).to receive(:environment)
        allow(IRB).to receive(:start)
        rage_cli.console
      end

      it "Fiber.await raises an error during the rage console (binding.irb)" do
        expect {
          Fiber.await(Fiber.schedule { :test })
        }.to raise_error(RuntimeError, "No scheduler is available!")
      end

      it "Fiber.schedule raises an error during the rage console (binding.irb)" do
        expect {
          Fiber.schedule { :test }
        }.to raise_error(RuntimeError, "No scheduler is available!")
      end
    end
  end
end

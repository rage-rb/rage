require "rage/cli"
require "tmpdir"
require "rake"
require "active_support/inflector"

RSpec.describe Rage::CLICodeGenerator do
  subject(:rage_cli_code_generator) { described_class.new }

  around(:example, :with_temp_directory) do |example|
    Dir.mktmpdir do |tmpdir|
      rage_cli_code_generator.destination_root = tmpdir
      example.run
    end
  end

  shared_examples "file generator" do |expected_file_path:, expected_file_name:, expected_class:|
    it "creates a file from template" do
      subject

      expected_path = File.join(rage_cli_code_generator.destination_root, expected_file_path, expected_file_name)
      expect(File).to exist(expected_path)

      content = File.read(expected_path)
      expect(content).to include("class #{expected_class}")
    end
  end

  describe "#migration" do
    subject { rage_cli_code_generator.migration(input_name) }

    before do
      allow(Rake::Task).to receive(:[]).with("db:new_migration").and_return(instance_double(Rake::Task, invoke: true))
    end

    context "when name is nil" do
      let(:input_name) { nil }

      it "returns help" do
        expect(rage_cli_code_generator).to receive(:help).with("migration")

        subject
      end
    end

    context "when name is present" do
      let(:input_name) { "Test" }

      it "generates a migration" do
        expect(Rake::Task["db:new_migration"]).to receive(:invoke).with("Test")

        subject
      end
    end
  end

  describe "#model", :with_temp_directory do
    subject { rage_cli_code_generator.model(input_name) }

    context "when name is nil" do
      let(:input_name) { nil }

      it "returns help" do
        expect(rage_cli_code_generator).to receive(:help).with("model")

        subject
      end
    end

    context "when name is present" do
      let(:input_name) { "A::B::Tests" }

      before { allow(rage_cli_code_generator).to receive(:migration) }

      it "generates a migration" do
        expect(rage_cli_code_generator).to receive(:migration).with("create_A::B::Tests")

        subject
      end

      it_behaves_like "file generator",
        expected_file_name: "test.rb",
        expected_file_path: "app/models/a/b",
        expected_class: "A::B::Test"
    end
  end

  describe "#controller", :with_temp_directory do
    subject { rage_cli_code_generator.controller(input_name) }

    context "when name is nil" do
      let(:input_name) { nil }

      it "returns help" do
        expect(rage_cli_code_generator).to receive(:help).with("controller")

        subject
      end
    end

    context "when name is present" do
      context "and ActiveSupport::Inflector is not available" do
        let(:input_name) { "my_controller" }

        before { hide_const("ActiveSupport::Inflector") }

        it "raises error" do
          expect { rage_cli_code_generator.controller("test") }.to(
            raise_error(LoadError, <<~ERR
              ActiveSupport::Inflector is required to run this command. Add the following line to your Gemfile:
              gem "activesupport", require: "active_support/inflector"
            ERR
            )
          )
        end
      end

      context "and ActiveSupport::Inflector is available" do
        context "with a singular name without suffix" do
          let(:input_name) { "test" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers",
            expected_class: "TestController"
        end

        context "with a plural name without suffix" do
          let(:input_name) { "tests" }

          it_behaves_like "file generator",
            expected_file_name: "tests_controller.rb",
            expected_file_path: "app/controllers",
            expected_class: "TestsController"
        end

        context "with 'Controller' suffix in CamelCase" do
          let(:input_name) { "TestController" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers",
            expected_class: "TestController"
        end

        context "with 'controller' suffix in lowercase" do
          let(:input_name) { "testcontroller" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers",
            expected_class: "TestController"
        end

        context "with '_controller' suffix in snake_case" do
          let(:input_name) { "test_controller" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers",
            expected_class: "TestController"
        end

        context "with slash-separated namespace" do
          let(:input_name) { "admin/test_controller" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers/admin",
            expected_class: "Admin::TestController"
        end

        context "with a double-colon namespace" do
          let(:input_name) { "A::B::TestAPI" }

          it_behaves_like "file generator",
            expected_file_name: "test_api_controller.rb",
            expected_file_path: "app/controllers/a/b",
            expected_class: "A::B::TestAPIController"
        end

        context "with absolute namespace" do
          let(:input_name) { "::Admin::Test" }

          it_behaves_like "file generator",
            expected_file_name: "test_controller.rb",
            expected_file_path: "app/controllers/admin",
            expected_class: "::Admin::TestController"
        end
      end
    end
  end
end

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

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

  describe "#events" do
    subject { rage_cli.events }

    before do
      allow(rage_cli).to receive(:environment)
      Rage::Events.__reset_subscribers
    end

    after do
      Rage::Events.__reset_subscribers
    end

    def cli_event(str) = "\e[90m#{str}\e[0m"
    def cli_subscriber(str) = "\e[1m#{str}\e[0m"

    def def_event(name, parent: Object, &block)
      event = Class.new(parent)
      event.class_eval(&block) if block
      stub_const(name, event)

      event
    end

    def def_subscriber(name, subscribe_to:)
      subscriber = Class.new do
        include Rage::Events::Subscriber
      end

      subscriber.subscribe_to(subscribe_to)
      stub_const(name, subscriber)

      subscriber
    end

    context "with no subscribers" do
      it "doesn't error out" do
        expect { subject }.to output("").to_stdout
      end
    end

    context "with one subscriber" do
      before do
        user_created = def_event("UserCreated")
        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   └─ #{cli_subscriber("SendWelcomeEmail")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with multiple subscribers" do
      before do
        user_created = def_event("UserCreated")

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   └─ #{cli_subscriber("GenerateAvatar")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with multiple events" do
      before do
        user_created = def_event("UserCreated")
        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)

        order_created = def_event("OrderCreated")
        def_subscriber("ScheduleDelivery", subscribe_to: order_created)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   └─ #{cli_subscriber("GenerateAvatar")}
          ├─ #{cli_event("OrderCreated")}
          │   └─ #{cli_subscriber("ScheduleDelivery")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end

      context "with filtered events" do
        subject { rage_cli.events("OrderCreated") }

        let(:expected) do
          <<~CLI
            ├─ #{cli_event("OrderCreated")}
            │   └─ #{cli_subscriber("ScheduleDelivery")}
          CLI
        end

        it "correctly outputs subscribers tree" do
          expect { subject }.to output(expected).to_stdout
        end
      end
    end

    context "with two levels" do
      before do
        event = def_event("Event")
        def_subscriber("LogEvent", subscribe_to: event)

        user_event = def_event("UserEvent", parent: event)
        user_created = def_event("UserCreated", parent: user_event)

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)
        def_subscriber("UpdateUsersCache", subscribe_to: user_event)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   ├─ #{cli_subscriber("GenerateAvatar")}
          |   └─ #{cli_event("UserEvent")}
          │      ├─ #{cli_subscriber("UpdateUsersCache")}
          |      └─ #{cli_event("Event")}
          │         └─ #{cli_subscriber("LogEvent")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with three levels" do
      before do
        trackable_event = Module.new
        stub_const("TrackableEvent", trackable_event)

        instrumented_event = Module.new do
          include TrackableEvent
        end
        stub_const("InstrumentedEvent", instrumented_event)

        event = def_event("Event")

        user_event = def_event("UserEvent", parent: event) do
          include InstrumentedEvent
        end
        user_created = def_event("UserCreated", parent: user_event)

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)
        def_subscriber("UpdateUsersCache", subscribe_to: user_event)

        def_subscriber("LogEvent", subscribe_to: event)
        def_subscriber("TrackPublishedAt", subscribe_to: trackable_event)
        def_subscriber("ReportMetrics", subscribe_to: instrumented_event)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   ├─ #{cli_subscriber("GenerateAvatar")}
          |   └─ #{cli_event("UserEvent")}
          │      ├─ #{cli_subscriber("UpdateUsersCache")}
          |      └─ #{cli_event("InstrumentedEvent")}
          │         ├─ #{cli_subscriber("ReportMetrics")}
          |         └─ #{cli_event("TrackableEvent")}
          │            └─ #{cli_subscriber("TrackPublishedAt")}
          |      └─ #{cli_event("Event")}
          │         └─ #{cli_subscriber("LogEvent")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with one empty level" do
      before do
        event = def_event("Event")
        def_subscriber("LogEvent", subscribe_to: event)

        user_event = def_event("UserEvent", parent: event)
        user_created = def_event("UserCreated", parent: user_event)

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   ├─ #{cli_subscriber("GenerateAvatar")}
          |   └─ #{cli_event("UserEvent")}
          |      └─ #{cli_event("Event")}
          │         └─ #{cli_subscriber("LogEvent")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with two empty levels" do
      before do
        trackable_event = Module.new do
          include Module.new
        end
        stub_const("TrackableEvent", trackable_event)

        instrumented_event = Module.new do
          include TrackableEvent
        end
        stub_const("InstrumentedEvent", instrumented_event)

        event = def_event("Event")
        user_event = def_event("UserEvent", parent: event) do
          include InstrumentedEvent
        end
        user_created = def_event("UserCreated", parent: user_event)

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("TrackPublishedAt", subscribe_to: trackable_event)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          |   └─ #{cli_event("UserEvent")}
          |      └─ #{cli_event("InstrumentedEvent")}
          |         └─ #{cli_event("TrackableEvent")}
          │            └─ #{cli_subscriber("TrackPublishedAt")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end

    context "with three levels and one empty level" do
      before do
        trackable_event = Module.new
        stub_const("TrackableEvent", trackable_event)

        instrumented_event = Module.new do
          include TrackableEvent
        end
        stub_const("InstrumentedEvent", instrumented_event)

        event = def_event("Event")

        user_event = def_event("UserEvent", parent: event) do
          include InstrumentedEvent
        end
        user_created = def_event("UserCreated", parent: user_event)

        def_subscriber("SendWelcomeEmail", subscribe_to: user_created)
        def_subscriber("GenerateAvatar", subscribe_to: user_created)
        def_subscriber("UpdateUsersCache", subscribe_to: user_event)

        def_subscriber("LogEvent", subscribe_to: event)
        def_subscriber("TrackPublishedAt", subscribe_to: trackable_event)
      end

      let(:expected) do
        <<~CLI
          ├─ #{cli_event("UserCreated")}
          │   ├─ #{cli_subscriber("SendWelcomeEmail")}
          │   ├─ #{cli_subscriber("GenerateAvatar")}
          |   └─ #{cli_event("UserEvent")}
          │      ├─ #{cli_subscriber("UpdateUsersCache")}
          |      └─ #{cli_event("InstrumentedEvent")}
          |         └─ #{cli_event("TrackableEvent")}
          │            └─ #{cli_subscriber("TrackPublishedAt")}
          |      └─ #{cli_event("Event")}
          │         └─ #{cli_subscriber("LogEvent")}
        CLI
      end

      it "correctly outputs subscribers tree" do
        expect { subject }.to output(expected).to_stdout
      end
    end
  end
end

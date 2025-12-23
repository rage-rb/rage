# frozen_string_literal: true

RSpec.describe Rage::Telemetry::Spans do
  subject { Rage::Telemetry.tracer }

  let(:handlers_map) { { described_class.id => [Rage::Telemetry::HandlerRef[handler, :test_span]] } }
  let(:verifier) { double }

  let(:handler) do
    Class.new do
      def self.test_span(**)
        verifier.call(**)
        yield
      end
    end
  end

  before do
    allow(Rage.config.telemetry).to receive(:handlers_map).and_return(handlers_map)
    allow(handler).to receive(:verifier).and_return(verifier)
    subject.setup
  end

  around do |example|
    Rage::Telemetry.instance_variable_set(:@tracer, nil)
    example.run
    Rage::Telemetry.instance_variable_set(:@tracer, nil)
  end

  describe described_class::AwaitFiber do
    before do
      allow(Fiber).to receive(:schedule) do |&block|
        fiber = Fiber.new(blocking: true, &block)
        fiber.resume
        fiber
      end

      allow(Fiber).to receive(:await).and_call_original
    end

    it "passes correct arguments" do
      f1 = Fiber.schedule {}
      f2 = Fiber.schedule {}

      expect(verifier).to receive(:call).with({ id: "core.fiber.await", name: "Fiber.await", fibers: [f1, f2] })

      Fiber.await([f1, f2])
    end
  end

  describe described_class::DispatchFiber do
    before do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
      allow(Fiber).to receive(:schedule).and_call_original
    end

    after do
      Fiber.set_scheduler(nil)
    end

    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({ id: "core.fiber.dispatch", name: "Fiber.dispatch" })

      within_reactor do
        proc {}
      end
    end
  end

  describe described_class::SpawnFiber do
    before do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
      allow(Fiber).to receive(:schedule).and_call_original
    end

    after do
      Fiber.set_scheduler(nil)
    end

    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({
        id: "core.fiber.spawn", name: "Fiber.schedule", parent: instance_of(Fiber)
      })

      within_reactor do
        Fiber.schedule {}
        proc {}
      end
    end
  end

  describe described_class::EnqueueDeferredTask do
    let(:task_class) do
      Class.new do
        include Rage::Deferred::Task
      end
    end

    before do
      stub_const("MyTestTask", task_class)
      allow_any_instance_of(Rage::Deferred::Queue).to receive(:enqueue)
      allow(Rage::Deferred::Context).to receive(:get_or_create_user_context).and_return(:test_user_context)
    end

    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({
        id: "deferred.task.enqueue", name: "MyTestTask#enqueue", task_class: MyTestTask, task_context: :test_user_context
      })

      MyTestTask.enqueue
    end
  end

  describe described_class::ProcessDeferredTask do
    let(:task_class) do
      Class.new do
        include Rage::Deferred::Task
      end
    end

    before do
      stub_const("MyTestTask", task_class)
      allow(Rage).to receive(:logger).and_return(Rage::Logger.new(STDOUT))
      allow(Rage::Deferred::Context).to receive(:get_or_create_user_context).and_return(:test_user_context)
    end

    it "passes correct arguments" do
      task = MyTestTask.new

      expect(verifier).to receive(:call).with({
        id: "deferred.task.process", name: "MyTestTask#perform", task: task, task_class: MyTestTask, task_context: :test_user_context
      })

      task.__perform(Rage::Deferred::Context.build(nil, [], {}))
    end
  end

  describe described_class::PublishEvent do
    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({
        id: "events.event.publish",
        name: "Events.publish(Symbol)",
        event: :test_event,
        context: nil,
        subscriber_classes: []
      })

      Rage::Events.publish(:test_event)
    end

    context "with context" do
      it "passes correct arguments" do
        expect(verifier).to receive(:call).with({
          id: "events.event.publish",
          name: "Events.publish(Symbol)",
          event: :test_event,
          context: { test_context: true },
          subscriber_classes: []
        })

        Rage::Events.publish(:test_event, context: { test_context: true })
      end
    end

    context "with subscribers" do
      let(:subscriber_class) do
        Class.new do
          include Rage::Events::Subscriber
          subscribe_to Symbol
        end
      end

      before do
        stub_const("MyTestSubscriber", subscriber_class)
        allow(Rage).to receive(:logger).and_return(Rage::Logger.new(STDOUT))
      end

      it "passes correct arguments" do
        expect(verifier).to receive(:call).with({
          id: "events.event.publish",
          name: "Events.publish(Symbol)",
          event: :test_event,
          context: nil,
          subscriber_classes: [MyTestSubscriber]
        })

        Rage::Events.publish(:test_event)
      end
    end
  end

  describe described_class::ProcessEventSubscriber do
    let(:subscriber_class) do
      Class.new do
        include Rage::Events::Subscriber
        subscribe_to Symbol
      end
    end

    before do
      stub_const("MyTestSubscriber", subscriber_class)
      allow(Rage).to receive(:logger).and_return(Rage::Logger.new(STDOUT))
    end

    it "passes correct arguments" do
      subscriber = MyTestSubscriber.new

      expect(verifier).to receive(:call).with({
        id: "events.subscriber.process",
        name: "MyTestSubscriber#call",
        subscriber: subscriber,
        event: :test_event,
        context: nil
      })

      subscriber.__call(:test_event)
    end

    context "with context" do
      let(:subscriber_class) do
        Class.new do
          include Rage::Events::Subscriber
          subscribe_to Symbol

          def call(_, _)
          end
        end
      end

      it "passes correct arguments" do
        subscriber = MyTestSubscriber.new

        expect(verifier).to receive(:call).with({
          id: "events.subscriber.process",
          name: "MyTestSubscriber#call",
          subscriber: subscriber,
          event: :test_event,
          context: { test_context: true }
        })

        subscriber.__call(:test_event, context: { test_context: true })
      end
    end
  end

  describe described_class::ProcessControllerAction do
    let(:controller_class) do
      Class.new(RageController::API) do
        def index
        end
      end
    end

    before do
      stub_const("MyTestController", controller_class)
      controller_class.__register_action(:index)
    end

    it "passes correct arguments" do
      controller = MyTestController.new({}, { action: :index })

      expect(verifier).to receive(:call).with({
        id: "controller.action.process", name: "MyTestController#index", controller: controller
      })

      controller.__run_index
    end
  end

  describe described_class::ProcessCableConnection do
    let(:connection_class) do
      Class.new(Rage::Cable::Connection) do
      end
    end

    let(:ws_connection) { double(env: {}) }

    before do
      stub_const("RageCable::Connection", connection_class)
    end

    context "with connect action" do
      it "passes correct arguments" do
        router = Rage::Cable::Router.new

        expect(verifier).to receive(:call).with({
          id: "cable.connection.process",
          name: "RageCable::Connection#connect",
          connection: instance_of(RageCable::Connection),
          action: :connect,
          env: equal(ws_connection.env)
        })

        router.process_connection(ws_connection)
      end
    end

    context "with disconnect action" do
      it "passes correct arguments" do
        router = Rage::Cable::Router.new

        expect(verifier).to receive(:call).with({
          id: "cable.connection.process",
          name: "RageCable::Connection#disconnect",
          connection: instance_of(RageCable::Connection),
          action: :disconnect,
          env: equal(ws_connection.env)
        })

        router.process_disconnection(ws_connection)
      end
    end
  end

  describe described_class::ProcessCableAction do
    let(:channel_class) do
      Class.new(Rage::Cable::Channel) do
        def receive
        end
      end
    end

    let(:ws_connection) { double(env: :test_rack_env) }

    before do
      stub_const("MyTestChannel", channel_class)
      channel_class.__register_actions
    end

    it "passes correct arguments" do
      channel = MyTestChannel.new(ws_connection, nil, nil)

      expect(verifier).to receive(:call).with({
        id: "cable.action.process",
        name: "MyTestChannel#receive",
        channel: channel,
        action: :receive,
        env: :test_rack_env,
        data: nil
      })

      channel.__run_action(:receive)
    end

    context "with data" do
      let(:channel_class) do
        Class.new(Rage::Cable::Channel) do
          def receive(_)
          end
        end
      end

      it "passes correct arguments" do
        channel = MyTestChannel.new(ws_connection, nil, nil)

        expect(verifier).to receive(:call).with({
          id: "cable.action.process",
          name: "MyTestChannel#receive",
          channel: channel,
          action: :receive,
          env: :test_rack_env,
          data: { message: "test" }
        })

        channel.__run_action(:receive, { message: "test" })
      end
    end

    context "with custom action" do
      let(:channel_class) do
        Class.new(Rage::Cable::Channel) do
          def appear
          end
        end
      end

      it "passes correct arguments" do
        channel = MyTestChannel.new(ws_connection, nil, nil)

        expect(verifier).to receive(:call).with({
          id: "cable.action.process",
          name: "MyTestChannel#appear",
          channel: channel,
          action: :appear,
          env: :test_rack_env,
          data: nil
        })

        channel.__run_action(:appear)
      end
    end
  end

  describe described_class::BroadcastCableStream do
    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({
        id: "cable.stream.broadcast",
        name: "Rage::Cable.broadcast",
        stream: "my_test_stream"
      })

      Rage::Cable.broadcast("my_test_stream", {})
    end
  end

  describe described_class::CreateWebsocketConnection do
    let(:env) { { "HTTP_ORIGIN" => "localhost" } }

    it "passes correct arguments" do
      expect(verifier).to receive(:call).with({
        id: "cable.websocket.handshake", name: "WebSocket.handshake", env: env
      })

      Rage::Cable.application.call(env)
    end
  end
end

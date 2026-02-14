# frozen_string_literal: true

module EventsLoggerSpec
  EventWithLog = Data.define

  class EventWithLogSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventWithLog

    def call(_)
      Rage.logger.info "test"
    end
  end

  InheritedEvent = Data.define

  class InheritedEventSubscriberBase
    include Rage::Events::Subscriber
  end

  class InheritedEventSubscriber < InheritedEventSubscriberBase
    subscribe_to InheritedEvent

    def call(_)
      Rage.logger.info "test"
    end
  end

  EventTriggeringEvent = Data.define
  NestedEvent = Data.define

  class EventTriggeringEventSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventTriggeringEvent

    def call(_)
      Rage.logger.info "test 1"
      Rage::Events.publish(NestedEvent.new)
      Rage.logger.info "test 3"
    end
  end

  class NestedEventSubscriber
    include Rage::Events::Subscriber
    subscribe_to NestedEvent

    def call(_)
      Rage.logger.info "test 2"
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow(Rage).to receive(:logger).and_return(Rage::Logger.new(output))
  end

  let(:output) { StringIO.new }

  context "with plain subscriber" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::EventWithLogSubscriber")
        expect(log).to include("message=test")
      end

      described_class.publish(EventsLoggerSpec::EventWithLog.new)
    end
  end

  context "with inherited subscriber" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::InheritedEventSubscriber")
        expect(log).to include("message=test")
      end

      described_class.publish(EventsLoggerSpec::InheritedEvent.new)
    end
  end

  context "with nested publish calls" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::EventTriggeringEventSubscriber")
        expect(log).to include("message=test 1")
      end

      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::NestedEventSubscriber")
        expect(log).to include("message=test 2")
      end

      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::EventTriggeringEventSubscriber")
        expect(log).to include("message=test 3")
      end

      described_class.publish(EventsLoggerSpec::EventTriggeringEvent.new)
    end
  end
end

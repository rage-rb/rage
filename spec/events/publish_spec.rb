# frozen_string_literal: true

module EventsPublishSpec
  class BaseSubscriber
    include Rage::Events::Subscriber

    def handle(event)
      subscribers << self.class
      events << event
    end
  end

  NoSubscribersEvent = Data.define

  Event1 = Data.define

  class Subscriber1 < BaseSubscriber
    subscribe_to Event1
  end

  Event2_1 = Data.define
  Event2_2 = Data.define

  class Subscriber2 < BaseSubscriber
    subscribe_to Event2_1, Event2_2
  end

  Event3Base = Class.new(Data)
  Event3 = Event3Base.define

  class Subscriber3 < BaseSubscriber
    subscribe_to Event3Base
  end

  Event4Mixin = Module.new
  Event4 = Data.define do
    include Event4Mixin
  end

  class Subscriber4 < BaseSubscriber
    subscribe_to Event4Mixin
  end

  Event5Mixin = Module.new
  Event5Base = Class.new(Data) do
    include Event5Mixin
  end
  Event5 = Event5Base.define

  class Subscriber5_1 < BaseSubscriber
    subscribe_to Event5Mixin
  end

  class Subscriber5_2 < BaseSubscriber
    subscribe_to Event5Base
  end

  class Subscriber5_3 < BaseSubscriber
    subscribe_to Event5
  end

  class Subscriber5_4 < BaseSubscriber
    subscribe_to Event5
  end

  Event6Mixin = Module.new
  Event6 = Data.define do
    include Event6Mixin
  end

  class Subscriber6_1 < BaseSubscriber
    subscribe_to Event6Mixin, Event6
  end

  class Subscriber6_2 < BaseSubscriber
    subscribe_to Event6
  end

  Event7 = Data.define

  class Subscriber7_1
    include Rage::Events::Subscriber
    subscribe_to Event7

    def handle(_)
      raise "test error"
    end
  end

  class Subscriber7_2 < BaseSubscriber
    subscribe_to Event7
  end

  Event8 = Data.define
  Event8_1 = Data.define

  class Subscriber8 < BaseSubscriber
    subscribe_to Event8
  end

  class Subscriber8_1 < Subscriber8
    subscribe_to Event8_1
  end

  Event9 = Data.define
  Event9_1 = Class.new(Event9)

  class Subscriber9 < BaseSubscriber
    subscribe_to Event9
  end

  class Subscriber9_1 < Subscriber9
    subscribe_to Event9_1
  end

  class Subscriber10 < BaseSubscriber
    subscribe_to Symbol
  end

  class Subscriber11 < BaseSubscriber
    subscribe_to StandardError
  end
end

RSpec.describe Rage::Events do
  before do
    allow_any_instance_of(EventsPublishSpec::BaseSubscriber).to receive(:subscribers).and_return(subscribers)
    allow_any_instance_of(EventsPublishSpec::BaseSubscriber).to receive(:events).and_return(events)

    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:with_context).and_yield
  end

  let(:subscribers) { [] }
  let(:events) { [] }
  let(:logger) { double }

  context "with no subscribers" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::NoSubscribersEvent.new)

      expect(subscribers).to be_empty
      expect(events).to be_empty
    end
  end

  context "with one subscriber" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::Event1.new)

      expect(subscribers).to eq([EventsPublishSpec::Subscriber1])
      expect(events).to match([instance_of(EventsPublishSpec::Event1)])
    end
  end

  context "with a subscriber with multiple events" do
    it "correctly handles first event" do
      described_class.publish(EventsPublishSpec::Event2_1.new)

      expect(subscribers).to eq([EventsPublishSpec::Subscriber2])
      expect(events).to match([instance_of(EventsPublishSpec::Event2_1)])
    end

    it "correctly handles second event" do
      described_class.publish(EventsPublishSpec::Event2_2.new)

      expect(subscribers).to eq([EventsPublishSpec::Subscriber2])
      expect(events).to match([instance_of(EventsPublishSpec::Event2_2)])
    end
  end

  context "with base class subscriber" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::Event3.new)

      expect(subscribers).to eq([EventsPublishSpec::Subscriber3])
      expect(events).to match([instance_of(EventsPublishSpec::Event3)])
    end
  end

  context "with module subscriber" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::Event4.new)

      expect(subscribers).to eq([EventsPublishSpec::Subscriber4])
      expect(events).to match([instance_of(EventsPublishSpec::Event4)])
    end
  end

  context "with multiple subscribers" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::Event5.new)

      expect(subscribers).to match_array([
        EventsPublishSpec::Subscriber5_1,
        EventsPublishSpec::Subscriber5_2,
        EventsPublishSpec::Subscriber5_3,
        EventsPublishSpec::Subscriber5_4
      ])

      expect(events.length).to eq(4)
      events.each do |event|
        expect(event).to be_an_instance_of(EventsPublishSpec::Event5)
      end
    end
  end

  context "with duplicate subscribe" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::Event6.new)

      expect(subscribers).to match_array([EventsPublishSpec::Subscriber6_1, EventsPublishSpec::Subscriber6_2])
      expect(events).to match([instance_of(EventsPublishSpec::Event6), instance_of(EventsPublishSpec::Event6)])
    end
  end

  context "with exception inside subscriber" do
    it "correctly handles events" do
      expect(logger).to receive(:error).with(/test error/)

      expect {
        described_class.publish(EventsPublishSpec::Event7.new)
      }.not_to raise_error

      expect(subscribers).to eq([EventsPublishSpec::Subscriber7_2])
      expect(events).to match([instance_of(EventsPublishSpec::Event7)])
    end
  end

  context "with inherited subscriptions" do
    it "correctly handles events in base class" do
      described_class.publish(EventsPublishSpec::Event8.new)

      expect(subscribers).to match_array([EventsPublishSpec::Subscriber8])
      expect(events).to match([instance_of(EventsPublishSpec::Event8)])
    end

    it "correctly handles events in inherited class" do
      described_class.publish(EventsPublishSpec::Event8_1.new)

      expect(subscribers).to match_array([EventsPublishSpec::Subscriber8_1])
      expect(events).to match([instance_of(EventsPublishSpec::Event8_1)])
    end
  end

  context "with inherited subscriptions and inherited events" do
    it "correctly handles events in base class" do
      described_class.publish(EventsPublishSpec::Event9.new)

      expect(subscribers).to match_array([EventsPublishSpec::Subscriber9])
      expect(events).to match([instance_of(EventsPublishSpec::Event9)])
    end

    it "correctly handles events in inherited class" do
      described_class.publish(EventsPublishSpec::Event9_1.new)

      expect(subscribers).to match_array([EventsPublishSpec::Subscriber9, EventsPublishSpec::Subscriber9_1])
      expect(events).to match([instance_of(EventsPublishSpec::Event9_1), instance_of(EventsPublishSpec::Event9_1)])
    end
  end

  context "with symbol subscription" do
    it "correctly handles events" do
      described_class.publish(:test_event)
      expect(subscribers).to match_array([EventsPublishSpec::Subscriber10])
      expect(events).to match([:test_event])
    end

    it "ignores non-symbol publishes" do
      described_class.publish("test_event")
      expect(subscribers).to be_empty
      expect(events).to be_empty
    end
  end

  context "with error subscription" do
    it "correctly handles events" do
      error = ZeroDivisionError.new

      described_class.publish(error)
      expect(subscribers).to match_array([EventsPublishSpec::Subscriber11])
      expect(events).to match([error])
    end
  end
end

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

  EventWithOneSubscriber = Data.define

  class EventWithOneSubscriberSubscriber < BaseSubscriber
    subscribe_to EventWithOneSubscriber
  end

  EventWithMultipleEvents_1 = Data.define
  EventWithMultipleEvents_2 = Data.define

  class EventWithMultipleEventsSubsciber < BaseSubscriber
    subscribe_to EventWithMultipleEvents_1, EventWithMultipleEvents_2
  end

  EventWithParentBase = Class.new(Data)
  EventWithParent = EventWithParentBase.define

  class EventWithParentSubscriber < BaseSubscriber
    subscribe_to EventWithParentBase
  end

  EventWithMixinBase = Module.new
  EventWithMixin = Data.define do
    include EventWithMixinBase
  end

  class EventWithMixinSubscriber < BaseSubscriber
    subscribe_to EventWithMixinBase
  end

  EventWithMultipleSubscribersMixin = Module.new
  EventWithMultipleSubscribersBase = Class.new(Data) do
    include EventWithMultipleSubscribersMixin
  end
  EventWithMultipleSubscribers = EventWithMultipleSubscribersBase.define

  class EventWithMultipleSubscribersSubscriber_1 < BaseSubscriber
    subscribe_to EventWithMultipleSubscribersMixin
  end

  class EventWithMultipleSubscribersSubscriber_2 < BaseSubscriber
    subscribe_to EventWithMultipleSubscribersBase
  end

  class EventWithMultipleSubscribersSubscriber_3 < BaseSubscriber
    subscribe_to EventWithMultipleSubscribers
  end

  class EventWithMultipleSubscribersSubscriber_4 < BaseSubscriber
    subscribe_to EventWithMultipleSubscribers
  end

  EventWithDuplicateSubscribeMixin = Module.new
  EventWithDuplicateSubscribe = Data.define do
    include EventWithDuplicateSubscribeMixin
  end

  class EventWithDuplicateSubscribe_1 < BaseSubscriber
    subscribe_to EventWithDuplicateSubscribeMixin, EventWithDuplicateSubscribe
  end

  class EventWithDuplicateSubscribe_2 < BaseSubscriber
    subscribe_to EventWithDuplicateSubscribe
  end

  EventWithException = Data.define

  class EventWithExceptionSubscriber_1
    include Rage::Events::Subscriber
    subscribe_to EventWithException

    def handle(_)
      raise "test error"
    end
  end

  class EventWithExceptionSubscriber_2 < BaseSubscriber
    subscribe_to EventWithException
  end

  EventWithInheritedSubscriptionBase = Data.define
  EventWithInheritedSubscription = Data.define

  class EventWithInheritedSubscriptionSubscriberBase < BaseSubscriber
    subscribe_to EventWithInheritedSubscriptionBase
  end

  class EventWithInheritedSubscriptionSubscriber < EventWithInheritedSubscriptionSubscriberBase
    subscribe_to EventWithInheritedSubscription
  end

  EventWithChainBase = Data.define
  EventWithChain = Class.new(EventWithChainBase)

  class EventWithChainBaseSubscriber < BaseSubscriber
    subscribe_to EventWithChainBase
  end

  class EventWithChainSubscriber < EventWithChainBaseSubscriber
    subscribe_to EventWithChain
  end

  class SymbolSubscriber < BaseSubscriber
    subscribe_to Symbol
  end

  class ExceptionSubscriber < BaseSubscriber
    subscribe_to StandardError
  end

  EventWithOutsideSubscription = Data.define

  class EventWithOutsideSubscriptionSubscriber < BaseSubscriber
  end

  EventWithOutsideSubscriptionSubscriber.subscribe_to EventWithOutsideSubscription

  EventWithAppend_1 = Data.define
  EventWithAppend_2 = Data.define

  class EventWithAppendSubscriber < BaseSubscriber
    subscribe_to EventWithAppend_1
    subscribe_to EventWithAppend_2
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
      described_class.publish(EventsPublishSpec::EventWithOneSubscriber.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithOneSubscriberSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithOneSubscriber)])
    end
  end

  context "with a subscriber with multiple events" do
    it "correctly handles first event" do
      described_class.publish(EventsPublishSpec::EventWithMultipleEvents_1.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithMultipleEventsSubsciber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithMultipleEvents_1)])
    end

    it "correctly handles second event" do
      described_class.publish(EventsPublishSpec::EventWithMultipleEvents_2.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithMultipleEventsSubsciber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithMultipleEvents_2)])
    end
  end

  context "with base class subscriber" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithParent.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithParentSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithParent)])
    end
  end

  context "with module subscriber" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithMixin.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithMixinSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithMixin)])
    end
  end

  context "with multiple subscribers" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithMultipleSubscribers.new)

      expect(subscribers).to match_array([
        EventsPublishSpec::EventWithMultipleSubscribersSubscriber_1,
        EventsPublishSpec::EventWithMultipleSubscribersSubscriber_2,
        EventsPublishSpec::EventWithMultipleSubscribersSubscriber_3,
        EventsPublishSpec::EventWithMultipleSubscribersSubscriber_4
      ])

      expect(events.length).to eq(4)
      events.each do |event|
        expect(event).to be_an_instance_of(EventsPublishSpec::EventWithMultipleSubscribers)
      end
    end
  end

  context "with duplicate subscribe" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithDuplicateSubscribe.new)

      expect(subscribers).to match_array([EventsPublishSpec::EventWithDuplicateSubscribe_1, EventsPublishSpec::EventWithDuplicateSubscribe_2])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithDuplicateSubscribe), instance_of(EventsPublishSpec::EventWithDuplicateSubscribe)])
    end
  end

  context "with exception inside subscriber" do
    it "correctly handles events" do
      expect(logger).to receive(:error).with(/test error/)

      expect {
        described_class.publish(EventsPublishSpec::EventWithException.new)
      }.not_to raise_error

      expect(subscribers).to eq([EventsPublishSpec::EventWithExceptionSubscriber_2])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithException)])
    end
  end

  context "with inherited subscriptions" do
    it "correctly handles events in base class" do
      described_class.publish(EventsPublishSpec::EventWithInheritedSubscriptionBase.new)

      expect(subscribers).to match_array([EventsPublishSpec::EventWithInheritedSubscriptionSubscriber, EventsPublishSpec::EventWithInheritedSubscriptionSubscriberBase])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithInheritedSubscriptionBase), instance_of(EventsPublishSpec::EventWithInheritedSubscriptionBase)])
    end

    it "correctly handles events in inherited class" do
      described_class.publish(EventsPublishSpec::EventWithInheritedSubscription.new)

      expect(subscribers).to match_array([EventsPublishSpec::EventWithInheritedSubscriptionSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithInheritedSubscription)])
    end
  end

  context "with inherited subscriptions and inherited events" do
    it "correctly handles events in base class" do
      described_class.publish(EventsPublishSpec::EventWithChainBase.new)

      expect(subscribers).to match_array([EventsPublishSpec::EventWithChainSubscriber, EventsPublishSpec::EventWithChainBaseSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithChainBase), instance_of(EventsPublishSpec::EventWithChainBase)])
    end

    it "correctly handles events in inherited class" do
      described_class.publish(EventsPublishSpec::EventWithChain.new)

      expect(subscribers).to match_array([EventsPublishSpec::EventWithChainBaseSubscriber, EventsPublishSpec::EventWithChainSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithChain), instance_of(EventsPublishSpec::EventWithChain)])
    end
  end

  context "with symbol subscription" do
    it "correctly handles events" do
      described_class.publish(:test_event)
      expect(subscribers).to match_array([EventsPublishSpec::SymbolSubscriber])
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
      expect(subscribers).to match_array([EventsPublishSpec::ExceptionSubscriber])
      expect(events).to match([error])
    end
  end

  context "with outside subscription" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithOutsideSubscription.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithOutsideSubscriptionSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithOutsideSubscription)])
    end
  end

  context "with sequential subscriptions" do
    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithAppend_1.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithAppendSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithAppend_1)])
    end

    it "correctly handles events" do
      described_class.publish(EventsPublishSpec::EventWithAppend_2.new)

      expect(subscribers).to eq([EventsPublishSpec::EventWithAppendSubscriber])
      expect(events).to match([instance_of(EventsPublishSpec::EventWithAppend_2)])
    end
  end
end

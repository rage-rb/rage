# frozen_string_literal: true

module EventsDeferredSpec
  EventWithDeferred = Data.define

  class EventWithDeferredSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventWithDeferred, deferred: true
  end

  EventWithoutDeferred = Data.define

  class EventWithoutDeferredSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventWithoutDeferred, deferred: false
  end

  EventWithDeferredAndMetadata = Data.define

  class EventWithDeferredAndMetadataSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventWithDeferredAndMetadata, deferred: true

    def handle(event, metadata: nil)
    end
  end

  EventWithException = Data.define

  class EventWithExceptionSubscriber
    include Rage::Events::Subscriber
    subscribe_to EventWithException, deferred: true

    def handle(event)
      raise "test"
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow(logger).to receive(:with_context).and_yield
    allow(Rage).to receive(:logger).and_return(logger)
  end

  let(:logger) { double }

  context "with deferred subscriber" do
    it "is a deferred task" do
      expect(EventsDeferredSpec::EventWithDeferredSubscriber.ancestors).to include(Rage::Deferred::Task)
    end

    it "enqueues the task" do
      event = EventsDeferredSpec::EventWithDeferred.new
      expect(EventsDeferredSpec::EventWithDeferredSubscriber).to receive(:enqueue).with(event)
      described_class.publish(event)
    end

    context "when subscriber doesn't accept metadata" do
      it "ignores metadata when enqueueing task" do
        event = EventsDeferredSpec::EventWithDeferred.new
        expect(EventsDeferredSpec::EventWithDeferredSubscriber).to receive(:enqueue).with(event)
        described_class.publish(event, metadata: "test")
      end
    end

    context "when subscriber accepts metadata" do
      it "doesn't ignore metadata when enqueueing task" do
        event = EventsDeferredSpec::EventWithDeferredAndMetadata.new
        expect(EventsDeferredSpec::EventWithDeferredAndMetadataSubscriber).to receive(:enqueue).with(event, metadata: "test")
        described_class.publish(event, metadata: "test")
      end
    end

    context "with exception" do
      it "it raises Deferred::TaskFailed" do
        expect(logger).to receive(:error).with(/failed with exception: RuntimeError/)

        expect {
          EventsDeferredSpec::EventWithExceptionSubscriber.new.perform(EventsDeferredSpec::EventWithException.new)
        }.to raise_error(Rage::Deferred::TaskFailed)
      end
    end
  end

  context "with disabled deferring" do
    it "doesn't enqueue the task" do
      expect(EventsDeferredSpec::EventWithoutDeferredSubscriber.ancestors).not_to include(Rage::Deferred::Task)
      expect(EventsDeferredSpec::EventWithoutDeferredSubscriber).not_to receive(:enqueue)
      expect_any_instance_of(EventsDeferredSpec::EventWithoutDeferredSubscriber).to receive(:handle)

      described_class.publish(EventsDeferredSpec::EventWithoutDeferred.new)
    end
  end
end

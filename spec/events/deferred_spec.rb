# frozen_string_literal: true

module EventsDeferredSpec
  Event1 = Data.define

  class Subscriber1
    include Rage::Events::Subscriber
    subscribe_to Event1, deferred: true
  end

  Event2 = Data.define

  class Subscriber2
    include Rage::Events::Subscriber
    subscribe_to Event2, deferred: false
  end

  Event3 = Data.define

  class Subscriber3
    include Rage::Events::Subscriber
    subscribe_to Event3, deferred: true

    def handle(event, metadata: nil)
    end
  end
end

RSpec.describe Rage::Events do
  context "with deferred subscriber" do
    it "is a deferred task" do
      expect(EventsDeferredSpec::Subscriber1.ancestors).to include(Rage::Deferred::Task)
    end

    it "enqueues the task" do
      event = EventsDeferredSpec::Event1.new
      expect(EventsDeferredSpec::Subscriber1).to receive(:enqueue).with(event)
      described_class.publish(event)
    end

    context "when subscriber doesn't accept metadata" do
      it "ignores metadata when enqueing task" do
        event = EventsDeferredSpec::Event1.new
        expect(EventsDeferredSpec::Subscriber1).to receive(:enqueue).with(event)
        described_class.publish(event, metadata: "test")
      end
    end

    context "when subscriber accepts metadata" do
      it "ignores metadata when enqueing task" do
        event = EventsDeferredSpec::Event3.new
        expect(EventsDeferredSpec::Subscriber3).to receive(:enqueue).with(event, metadata: "test")
        described_class.publish(event, metadata: "test")
      end
    end
  end

  context "with disabled deferring" do
    it "doesn't enqueue the task" do
      expect(EventsDeferredSpec::Subscriber2.ancestors).not_to include(Rage::Deferred::Task)
      expect(EventsDeferredSpec::Subscriber2).not_to receive(:enqueue)

      logger = double
      allow(Rage).to receive(:logger).and_return(logger)
      allow(logger).to receive(:with_context).and_yield
      expect_any_instance_of(EventsDeferredSpec::Subscriber2).to receive(:handle)

      described_class.publish(EventsDeferredSpec::Event2.new)
    end
  end
end

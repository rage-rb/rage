# frozen_string_literal: true

module EventsContextSpec
  class BaseSubscriber
    include Rage::Events::Subscriber
  end

  EventNoContext = Data.define

  class SubscriberNoContext < BaseSubscriber
    subscribe_to EventNoContext

    def call(event)
      verifier.called
    end
  end

  EventRequiredContext = Data.define

  class SubscriberRequiredContext < BaseSubscriber
    subscribe_to EventRequiredContext

    def call(event, context:)
      verifier.called(context)
    end
  end

  EventOptionalNilContext = Data.define

  class SubscriberOptionalNilContext < BaseSubscriber
    subscribe_to EventOptionalNilContext

    def call(event, context: nil)
      verifier.called(context)
    end
  end

  EventOptionalArrayContext = Data.define

  class SubscriberOptionalArrayContext < BaseSubscriber
    subscribe_to EventOptionalArrayContext

    def call(event, context: [])
      verifier.called(context)
    end
  end

  EventSplatContext = Data.define

  class SubscriberSplatContext < BaseSubscriber
    subscribe_to EventSplatContext

    def call(event, **kw)
      verifier.called(kw)
    end
  end

  EventContextAndSplat = Data.define

  class SubscriberContextAndSplat < BaseSubscriber
    subscribe_to EventContextAndSplat

    def call(event, context: nil, **kw)
      verifier.called(context)
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow_any_instance_of(EventsContextSpec::BaseSubscriber).to receive(:verifier).and_return(verifier)

    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:with_context).and_yield
  end

  let(:verifier) { double }
  let(:logger) { double }
  let(:context) { { id: 123 } }

  context "when subscriber doesn't accept context" do
    let(:event) { EventsContextSpec::EventNoContext.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called)
        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called)
        described_class.publish(event)
      end
    end
  end

  context "when subscriber requires context" do
    let(:event) { EventsContextSpec::EventRequiredContext.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called) do |received_context|
          expect(received_context).to eq(context)
          expect(received_context).to be_frozen
        end

        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called).with({})
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts context" do
    let(:event) { EventsContextSpec::EventOptionalNilContext.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called) do |received_context|
          expect(received_context).to eq(context)
          expect(received_context).to be_frozen
        end

        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called).with(nil)
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts context with default value" do
    let(:event) { EventsContextSpec::EventOptionalArrayContext.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called) do |received_context|
          expect(received_context).to eq(context)
          expect(received_context).to be_frozen
        end

        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called).with([])
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts any keyword argument" do
    let(:event) { EventsContextSpec::EventSplatContext.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called) do |received_context|
          expect(received_context).to eq({ context: })
          expect(received_context[:context]).to be_frozen
        end

        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called).with({})
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts context and any keyword argument" do
    let(:event) { EventsContextSpec::EventContextAndSplat.new }

    context "when sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called) do |received_context|
          expect(received_context).to eq(context)
          expect(received_context).to be_frozen
        end

        described_class.publish(event, context:)
      end
    end

    context "when not sending context" do
      it "correctly passes context to subscriber" do
        expect(verifier).to receive(:called).with(nil)
        described_class.publish(event)
      end
    end
  end
end

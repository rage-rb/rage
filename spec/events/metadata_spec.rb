# frozen_string_literal: true

module EventsMetadataSpec
  class BaseSubscriber
    include Rage::Events::Subscriber
  end

  EventNoMetadata = Data.define

  class SubscriberNoMetadata < BaseSubscriber
    subscribe_to EventNoMetadata

    def handle(event)
      verifier.called
    end
  end

  EventRequiredMetadata = Data.define

  class SubscriberRequiredMetadata < BaseSubscriber
    subscribe_to EventRequiredMetadata

    def handle(event, metadata:)
      verifier.called(metadata)
    end
  end

  EventOptionalNilMetadata = Data.define

  class SubscriberOptionalNilMetadata < BaseSubscriber
    subscribe_to EventOptionalNilMetadata

    def handle(event, metadata: nil)
      verifier.called(metadata)
    end
  end

  EventOptionalArrayMetadata = Data.define

  class SubscriberOptionalArrayMetadata < BaseSubscriber
    subscribe_to EventOptionalArrayMetadata

    def handle(event, metadata: [])
      verifier.called(metadata)
    end
  end

  EventSplatMetadata = Data.define

  class SubscriberSplatMetadata < BaseSubscriber
    subscribe_to EventSplatMetadata

    def handle(event, **kw)
      verifier.called(kw)
    end
  end

  EventMetadataAndSplat = Data.define

  class SubscriberMetadataAndSplat < BaseSubscriber
    subscribe_to EventMetadataAndSplat

    def handle(event, metadata: nil, **kw)
      verifier.called(metadata)
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow_any_instance_of(EventsMetadataSpec::BaseSubscriber).to receive(:verifier).and_return(verifier)

    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:with_context).and_yield
  end

  let(:verifier) { double }
  let(:logger) { double }
  let(:metadata) { { id: 123 } }

  context "when subscriber doesn't accept metadata" do
    let(:event) { EventsMetadataSpec::EventNoMetadata.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called)
        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called)
        described_class.publish(event)
      end
    end
  end

  context "when subscriber requires metadata" do
    let(:event) { EventsMetadataSpec::EventRequiredMetadata.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called) do |received_metadata|
          expect(received_metadata).to eq(metadata)
          expect(received_metadata).to be_frozen
        end

        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called).with({})
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts metadata" do
    let(:event) { EventsMetadataSpec::EventOptionalNilMetadata.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called) do |received_metadata|
          expect(received_metadata).to eq(metadata)
          expect(received_metadata).to be_frozen
        end

        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called).with(nil)
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts metadata with default value" do
    let(:event) { EventsMetadataSpec::EventOptionalArrayMetadata.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called) do |received_metadata|
          expect(received_metadata).to eq(metadata)
          expect(received_metadata).to be_frozen
        end

        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called).with([])
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts any keyword argument" do
    let(:event) { EventsMetadataSpec::EventSplatMetadata.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called) do |received_metadata|
          expect(received_metadata).to eq({ metadata: })
          expect(received_metadata[:metadata]).to be_frozen
        end

        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called).with({})
        described_class.publish(event)
      end
    end
  end

  context "when subscriber accepts metadata and any keyword argument" do
    let(:event) { EventsMetadataSpec::EventMetadataAndSplat.new }

    context "when sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called) do |received_metadata|
          expect(received_metadata).to eq(metadata)
          expect(received_metadata).to be_frozen
        end

        described_class.publish(event, metadata:)
      end
    end

    context "when not sending metadata" do
      it "correctly passes metadata to subscriber" do
        expect(verifier).to receive(:called).with(nil)
        described_class.publish(event)
      end
    end
  end
end

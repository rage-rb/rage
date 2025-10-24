# frozen_string_literal: true

module EventsRescueFromSpec
  class BaseSubscriber
    include Rage::Events::Subscriber

    def handle(_)
      raise StandardError, "test"
    end
  end

  EventWithBlockRescueFrom = Data.define

  class EventWithBlockRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithBlockRescueFrom

    rescue_from StandardError do
      verifier.rescue_from
    end
  end

  EventWithBlockRescueFromWithArgument = Data.define

  class EventWithBlockRescueFromWithArgumentSubscriber < BaseSubscriber
    subscribe_to EventWithBlockRescueFromWithArgument

    rescue_from StandardError do |e|
      verifier.rescue_from(e)
    end
  end

  EventWithMethodRescueFrom = Data.define

  class EventWithMethodRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithMethodRescueFrom

    rescue_from StandardError, with: :exception_handler

    def exception_handler
      verifier.rescue_from
    end
  end

  EventWithMethodRescueFromWithArgument = Data.define

  class EventWithMethodRescueFromWithArgumentSubscriber < BaseSubscriber
    subscribe_to EventWithMethodRescueFromWithArgument

    rescue_from StandardError, with: :exception_handler

    def exception_handler(e)
      verifier.rescue_from(e)
    end
  end

  EventWithPrivateMethodRescueFrom = Data.define

  class EventWithPrivateMethodRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithPrivateMethodRescueFrom

    rescue_from StandardError, with: :exception_handler

    private

    def exception_handler
      verifier.rescue_from
    end
  end

  EventWithPrivateMethodRescueFromWithArgument = Data.define

  class EventWithPrivateMethodRescueFromWithArgumentSubscriber < BaseSubscriber
    subscribe_to EventWithPrivateMethodRescueFromWithArgument

    rescue_from StandardError, with: :exception_handler

    private

    def exception_handler(e)
      verifier.rescue_from(e)
    end
  end

  EventWithMultipleRescueFrom = Data.define(:type)

  class EventWithMultipleRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithMultipleRescueFrom

    rescue_from ZeroDivisionError do |e|
      verifier.rescue_from_zero_division(e)
    end

    rescue_from ArgumentError, with: :exception_handler

    def handle(event)
      if event.type == :argument_error
        raise ArgumentError, "test"
      elsif event.type == :zero_division_error
        raise ZeroDivisionError, "test"
      end
    end

    private

    def exception_handler(e)
      verifier.rescue_from_argument(e)
    end
  end

  EventWithNotMatchingRescueFrom = Data.define

  class EventWithNotMatchingRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithNotMatchingRescueFrom

    rescue_from ArgumentError do
      verifier.rescue_from
    end
  end

  EventWithMultipleErrors = Data.define(:type)

  class EventWithMultipleErrorsSubscriber < BaseSubscriber
    subscribe_to EventWithMultipleErrors

    rescue_from ArgumentError, ZeroDivisionError do |e|
      verifier.rescue_from(e)
    end

    def handle(event)
      if event.type == :zero_division_error
        raise ZeroDivisionError, "test"
      elsif event.type == :argument_error
        raise ArgumentError, "test"
      end
    end
  end

  EventWithOverridenRescueFrom = Data.define

  class EventWithOverridenRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithOverridenRescueFrom

    rescue_from StandardError, ArgumentError do |e|
      verifier.not_expected(e)
    end

    rescue_from ArgumentError do |e|
      verifier.rescue_from(e)
    end

    def handle(_)
      raise ArgumentError, "test"
    end
  end

  EventWithGenericRescueFrom = Data.define

  class EventWithGenericRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithGenericRescueFrom

    rescue_from StandardError do |e|
      verifier.rescue_from(e)
    end

    def handle(_)
      raise ZeroDivisionError, "test"
    end
  end

  EventWithReRaiseInBlockRescueFrom = Data.define

  class EventWithReRaiseInBlockRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithReRaiseInBlockRescueFrom

    rescue_from StandardError do |e|
      raise e
    end
  end

  EventWithReRaiseWithDifferentExceptionInBlockRescueFrom = Data.define

  class EventWithReRaiseWithDifferentExceptionInBlockRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithReRaiseWithDifferentExceptionInBlockRescueFrom

    rescue_from StandardError do |e|
      raise ZeroDivisionError, "test"
    end
  end

  EventWithReRaiseInMethodRescueFrom = Data.define

  class EventWithReRaiseInMethodRescueFromSubscriber < BaseSubscriber
    subscribe_to EventWithReRaiseInMethodRescueFrom

    rescue_from StandardError, with: :exception_handler

    private

    def exception_handler(e)
      raise e
    end
  end

  EventWithInheritedRescueFrom = Data.define

  class BaseEventWithInheritedRescueFromSubscriber < BaseSubscriber
    rescue_from StandardError do |e|
      verifier.rescue_from(e)
    end
  end

  class EventWithInheritedRescueFromSubscriber < BaseEventWithInheritedRescueFromSubscriber
    subscribe_to EventWithInheritedRescueFrom
  end

  EventWithOverridenInheritedRescueFrom = Data.define

  class BaseEventWithOverridenInheritedRescueFromSubscriber < BaseSubscriber
    rescue_from StandardError do |e|
      verifier.not_expected(e)
    end
  end

  class EventWithOverridenInheritedRescueFromSubscriber < BaseEventWithOverridenInheritedRescueFromSubscriber
    subscribe_to EventWithOverridenInheritedRescueFrom

    rescue_from StandardError do |e|
      verifier.rescue_from(e)
    end
  end

  EventWithMultipleInheritedRescueFrom = Data.define(:type)

  class BaseEventWithMultipleInheritedRescueFromSubscriber < BaseSubscriber
    rescue_from ArgumentError do |e|
      verifier.rescue_from_argument(e)
    end
  end

  class EventWithMultipleInheritedRescueFromSubscriber < BaseEventWithMultipleInheritedRescueFromSubscriber
    subscribe_to EventWithMultipleInheritedRescueFrom

    rescue_from ZeroDivisionError do |e|
      verifier.rescue_from_zero_division(e)
    end

    def handle(event)
      if event.type == :zero_division_error
        raise ZeroDivisionError, "test"
      elsif event.type == :argument_error
        raise ArgumentError, "test"
      end
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow_any_instance_of(EventsRescueFromSpec::BaseSubscriber).to receive(:verifier).and_return(verifier)

    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:with_context).and_yield
  end

  let(:verifier) { double }
  let(:logger) { double }

  context "with block rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from)
      described_class.publish(EventsRescueFromSpec::EventWithBlockRescueFrom.new)
    end
  end

  context "with block rescue_from with argument" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(StandardError))
      described_class.publish(EventsRescueFromSpec::EventWithBlockRescueFromWithArgument.new)
    end
  end

  context "with method rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from)
      described_class.publish(EventsRescueFromSpec::EventWithMethodRescueFrom.new)
    end
  end

  context "with method rescue_from with argument" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(StandardError))
      described_class.publish(EventsRescueFromSpec::EventWithMethodRescueFromWithArgument.new)
    end
  end

  context "with private method rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from)
      described_class.publish(EventsRescueFromSpec::EventWithPrivateMethodRescueFrom.new)
    end
  end

  context "with private method rescue_from with argument" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(StandardError))
      described_class.publish(EventsRescueFromSpec::EventWithPrivateMethodRescueFromWithArgument.new)
    end
  end

  context "with multiple rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from_zero_division).with(instance_of(ZeroDivisionError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleRescueFrom.new(type: :zero_division_error))
    end

    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from_argument).with(instance_of(ArgumentError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleRescueFrom.new(type: :argument_error))
    end
  end

  context "with not matching rescue_from" do
    it "correctly catches exceptions" do
      expect(logger).to receive(:error).with(/failed with exception: StandardError/)
      described_class.publish(EventsRescueFromSpec::EventWithNotMatchingRescueFrom.new)
    end
  end

  context "with multiple errors" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(ZeroDivisionError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleErrors.new(type: :zero_division_error))
    end

    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(ArgumentError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleErrors.new(type: :argument_error))
    end
  end

  context "with overriden rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(ArgumentError))
      described_class.publish(EventsRescueFromSpec::EventWithOverridenRescueFrom.new)
    end
  end

  context "with generic rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(ZeroDivisionError))
      described_class.publish(EventsRescueFromSpec::EventWithGenericRescueFrom.new)
    end
  end

  context "with reraise in block rescue_from" do
    it "correctly catches exceptions" do
      expect(logger).to receive(:error).with(/failed with exception: StandardError/)
      described_class.publish(EventsRescueFromSpec::EventWithReRaiseInBlockRescueFrom.new)
    end
  end

  context "with reraise with different exception in block rescue_from" do
    it "correctly catches exceptions" do
      expect(logger).to receive(:error).with(/failed with exception: ZeroDivisionError/)
      described_class.publish(EventsRescueFromSpec::EventWithReRaiseWithDifferentExceptionInBlockRescueFrom.new)
    end
  end

  context "with reraise in method rescue_from" do
    it "correctly catches exceptions" do
      expect(logger).to receive(:error).with(/failed with exception: StandardError/)
      described_class.publish(EventsRescueFromSpec::EventWithReRaiseInMethodRescueFrom.new)
    end
  end

  context "with inherited rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(StandardError))
      described_class.publish(EventsRescueFromSpec::EventWithInheritedRescueFrom.new)
    end
  end

  context "with overriden inherited rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from).with(instance_of(StandardError))
      described_class.publish(EventsRescueFromSpec::EventWithOverridenInheritedRescueFrom.new)
    end
  end

  context "with multiple inherited rescue_from" do
    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from_argument).with(instance_of(ArgumentError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleInheritedRescueFrom.new(type: :argument_error))
    end

    it "correctly catches exceptions" do
      expect(verifier).to receive(:rescue_from_zero_division).with(instance_of(ZeroDivisionError))
      described_class.publish(EventsRescueFromSpec::EventWithMultipleInheritedRescueFrom.new(type: :zero_division_error))
    end
  end
end

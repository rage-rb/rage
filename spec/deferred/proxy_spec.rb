# frozen_string_literal: true

RSpec.describe Rage::Deferred::Proxy do
  let(:test_class) do
    Class.new do
      def do_something(arg1, kwarg1: "default")
        [arg1, kwarg1]
      end
    end
  end

  let(:instance) { test_class.new }
  let(:delay) { nil }
  let(:delay_until) { nil }
  let(:proxy) { described_class.new(instance, delay: delay, delay_until: delay_until) }

  before do
    allow(Rage::Deferred::Proxy::Wrapper).to receive(:enqueue)
  end

  describe "method delegation" do
    context "when the instance responds to the method" do
      it "enqueues the method call with arguments" do
        proxy.do_something("test", kwarg1: "value")

        expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).with(
          instance,
          :do_something,
          "test",
          delay: nil,
          delay_until: nil,
          kwarg1: "value"
        )
      end

      context "with a delay option" do
        let(:delay) { 60 }

        it "passes the delay option to enqueue" do
          proxy.do_something("test")

          expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).with(
            instance,
            :do_something,
            "test",
            delay: 60,
            delay_until: nil
          )
        end
      end

      context "with a delay_until option" do
        let(:delay_until) { Time.now + 3600 }

        it "passes the delay_until option to enqueue" do
          proxy.do_something("test")

          expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).with(
            instance,
            :do_something,
            "test",
            delay: nil,
            delay_until: delay_until
          )
        end
      end

      it "defines the method on the proxy to avoid future method_missing calls" do
        proxy.do_something("first call")
        expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).once

        expect(proxy).to respond_to(:do_something)

        proxy.do_something("second call")
        expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).twice
      end
    end

    context "when the instance does not respond to the method" do
      it "raises a NoMethodError" do
        expect { proxy.non_existent_method }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#respond_to?" do
    it "returns true if the instance responds to the method" do
      expect(proxy.respond_to?(:do_something)).to be(true)
    end

    it "returns false if the instance does not respond to the method" do
      expect(proxy.respond_to?(:non_existent_method)).to be(false)
    end
  end

  describe "Rage::Deferred::Proxy::Wrapper" do
    describe "#perform" do
      it "calls the method on the instance" do
        wrapper = Rage::Deferred::Proxy::Wrapper.new
        expect(instance).to receive(:public_send).with(:do_something, "arg", kwarg: "val")
        wrapper.perform(instance, :do_something, "arg", kwarg: "val")
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Deferred::Proxy do
  let(:instance) { double("instance") }
  let(:proxy) { described_class.new(instance) }

  describe "method delegation" do
    before do
      allow(Rage::Deferred::Proxy::Wrapper).to receive(:enqueue)
    end

    it "correctly delegates the method call to the wrapper" do
      proxy.perform_async("test", key: "value")

      expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).with(
        instance, :perform_async, "test", delay: nil, delay_until: nil, key: "value"
      )
    end

    it "defines the method on the class after the first call" do
      proxy.perform_async("test")
      expect(described_class.instance_methods(false)).to include(:perform_async)

      # a spy would be better here, but this is a simple way to check
      # that method_missing isn't called again for the same method
      expect(proxy).not_to receive(:method_missing)
      proxy.perform_async("test 2")
    end

    context "with delay options" do
      let(:delay) { 30 }
      let(:delay_until) { Time.now + 60 }
      let(:proxy) { described_class.new(instance, delay: delay, delay_until: delay_until) }

      it "passes delay options to the wrapper" do
        proxy.do_something("arg")

        expect(Rage::Deferred::Proxy::Wrapper).to have_received(:enqueue).with(
          instance, :do_something, "arg", delay: delay, delay_until: delay_until
        )
      end
    end
  end

  describe "#respond_to_missing?" do
    it "returns true for any method" do
      expect(proxy.respond_to?(:any_method_name)).to be_truthy
    end
  end

  describe "Rage::Deferred::Proxy::Wrapper" do
    it "includes the Task module" do
      expect(Rage::Deferred::Proxy::Wrapper).to include(Rage::Deferred::Task)
    end

    it "calls the correct method on the instance" do
      wrapper = Rage::Deferred::Proxy::Wrapper.new
      expect(instance).to receive(:public_send).with(:method_name, "arg1", "arg2", key: "value")

      wrapper.perform(instance, :method_name, "arg1", "arg2", key: "value")
    end
  end
end

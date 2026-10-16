# frozen_string_literal: true

RSpec.describe Rage::Cable::Router do
  let(:env) { {} }
  let(:connection) { instance_double("Iodine::Connection") }

  before do
    allow(Rage).to receive_message_chain(:logger, :debug) do |&block|
      puts(block.call)
    end
  end

  describe "#process_connection" do
    subject { described_class.new(nil, Object).process_connection(connection, env) }

    let(:connection) { double }
    let(:cable_connection_class) { double }
    let(:cable_connection_instance) { double(__connect: nil, __identified_by_map: :test_identified_by) }

    before do
      stub_const("RageCable::Connection", cable_connection_class)
      allow(cable_connection_class).to receive(:new).and_return(cable_connection_instance)
    end

    context "when connection is accepted" do
      before do
        allow(cable_connection_instance).to receive(:rejected?).and_return(false)
      end

      it "accepts a connection" do
        expect(subject).to be(true)
      end

      it "populates the env hash" do
        subject
        expect(env["rage.identified_by"]).to eq(:test_identified_by)
        expect(env["rage.cable"]).to eq({})
      end
    end

    context "when connection is rejected" do
      before do
        allow(cable_connection_instance).to receive(:rejected?).and_return(true)
      end

      it "rejects a connection" do
        expect(subject).to be(false)
      end

      it "doesn't populate the env hash" do
        subject
        expect(env).to be_empty
      end
    end
  end

  describe "#process_subscription" do
    subject { described_class.new(nil, Object).process_subscription(connection, env, :test_identifier, channel_name, :test_params) }

    let(:channel_name) { "TestChannel" }
    let(:cable_channel_class) { double(name: "TestChannel") }
    let(:channel) { double("Rage::Cable::Channel") }

    before do
      allow(cable_channel_class).to receive(:__protocol=)
    end

    context "with correct channel name" do
      before do
        stub_const(channel_name, cable_channel_class)
        allow(cable_channel_class).to receive(:ancestors).and_return([Rage::Cable::Channel])

        env["rage.cable"] = {}
        env["rage.identified_by"] = :test_identified_by
      end

      it "accepts the subscription" do
        expect(cable_channel_class).to receive(:__register_actions).once
        expect(cable_channel_class).to receive(:new).with(connection, :test_params, :test_identified_by).and_return(channel)

        expect(channel).to receive(:__run_action).with(:subscribed)
        expect(channel).to receive(:subscription_rejected?).and_return(false)

        expect(subject).to eq(:subscribed)
        expect(env["rage.cable"][:test_identifier]).to eq(channel)
      end

      context "with rejection" do
        it "rejects the subscription" do
          expect(cable_channel_class).to receive(:__register_actions).once
          expect(cable_channel_class).to receive(:new).with(connection, :test_params, :test_identified_by).and_return(channel)

          expect(channel).to receive(:__run_action).with(:subscribed)
          expect(channel).to receive(:subscription_rejected?).and_return(true)

          expect(subject).to eq(:rejected)
          expect(env["rage.cable"]).to be_empty
        end
      end
    end

    context "with incorrect channel name" do
      let(:channel_name) { "Array" }

      it "rejects the subscription" do
        expect(subject).to eq(:invalid)
        expect(env).to be_empty
      end
    end

    context "with incorrect constant name" do
      let(:channel_name) { ";;;;;;;" }

      it "rejects the subscription" do
        expect(subject).to eq(:invalid)
        expect(env).to be_empty
      end
    end
  end

  describe "#process_message" do
    subject { described_class.new(nil, Object).process_message(nil, env, :test_identifier, :test_action, :test_data) }

    context "with existing subscription" do
      let(:channel) { double }

      before do
        env["rage.cable"] = { test_identifier: channel }
      end

      context "with existing action" do
        it "processes the message" do
          expect(channel).to receive(:__has_action?).with(:test_action).and_return(true)
          expect(channel).to receive(:__run_action).with(:test_action, :test_data)
          expect(subject).to eq(:processed)
        end
      end

      context "with unknown action" do
        it "discards the message" do
          expect(channel).to receive(:__has_action?).with(:test_action).and_return(false)
          expect(channel).not_to receive(:__run_action)
          expect(subject).to eq(:unknown_action)
        end
      end
    end

    context "with no subscription" do
      before do
        env["rage.cable"] = {}
      end

      it "discards the message" do
        expect(subject).to eq(:no_subscription)
      end
    end
  end

  describe "#process_unsubscription" do
    subject { described_class.new(nil, Object).process_unsubscription(nil, env, :test_identifier) }

    let(:channel) { double("Rage::Cable::Channel") }

    context "with existing subscription" do
      before do
        env["rage.cable"] = { test_identifier: channel }
      end

      it "runs #unsubscribed" do
        expect(channel).to receive(:__run_action).with(:unsubscribed)
        subject
      end

      it "removes the channel instance" do
        allow(channel).to receive(:__run_action)
        subject
        expect(env["rage.cable"]).to be_empty
      end
    end

    context "with invalid subscription" do
      before do
        env["rage.cable"] = { new_identifier: channel }
      end

      it "doesn't raise error" do
        expect { subject }.not_to raise_error
      end
    end
  end

  describe "#process_disconnection" do
    subject { described_class.new(nil, Object).process_disconnection(nil, env) }

    context "with existing subscription" do
      let(:channel) { double }

      before do
        env["rage.cable"] = { test_identifier: channel }
      end

      it "runs the unsubscribed callback" do
        expect(channel).to receive(:__run_action).with(:unsubscribed)
        subject
      end
    end

    context "with no subscription" do
      before do
        env["rage.cable"] = nil
      end

      it "runs successfully" do
        expect { subject }.not_to raise_error
      end
    end

    context "with connection" do
      let(:cable_connection_class) { double }
      let(:cable_connection_instance) { double(__connect: nil, __identified_by_map: :test_identified_by) }

      before do
        stub_const("RageCable::Connection", cable_connection_class)
        allow(cable_connection_class).to receive(:new).and_return(cable_connection_instance)
      end

      it "calls disconnect on the connection class" do
        expect(cable_connection_instance).to receive(:__disconnect).once
        subject
      end
    end
  end

  describe "namespace support" do
    let(:custom_namespace) do
      Module.new do
        def self.name
          "CustomNamespace"
        end
      end
    end

    describe "#process_subscription with namespace" do
      let(:channel_class) do
        Class.new(Rage::Cable::Channel) do
          def self.name
            "ChatChannel"
          end
        end
      end
      let(:protocol) { double(supports_rpc?: true) }

      before do
        env["rage.cable"] = {}
        env["rage.identified_by"] = {}
        custom_namespace.const_set(:ChatChannel, channel_class)
      end

      after do
        custom_namespace.send(:remove_const, :ChatChannel) if custom_namespace.const_defined?(:ChatChannel)
      end

      it "looks up channels within the namespace" do
        router = described_class.new(protocol, custom_namespace)
        result = router.process_subscription(connection, env, :test_identifier, "ChatChannel", {})

        expect(result).to eq(:subscribed)
      end

      it "does not find channels outside the namespace" do
        stub_const("GlobalChannel", Class.new(Rage::Cable::Channel))
        router = described_class.new(protocol, custom_namespace)
        result = router.process_subscription(connection, env, :test_identifier, "GlobalChannel", {})

        expect(result).to eq(:invalid)
      end
    end

    describe "#init_connection_class with namespace" do
      let(:namespaced_connection_class) do
        Class.new(Rage::Cable::Connection)
      end

      context "with RageCable::Connection in namespace" do
        before do
          rage_cable_module = Module.new
          rage_cable_module.const_set(:Connection, namespaced_connection_class)
          custom_namespace.const_set(:RageCable, rage_cable_module)
        end

        after do
          custom_namespace.send(:remove_const, :RageCable) if custom_namespace.const_defined?(:RageCable)
        end

        it "uses the namespaced connection class" do
          router = described_class.new(nil, custom_namespace)
          cable_connection_instance = double(__connect: nil, rejected?: false, __identified_by_map: {})
          expect(namespaced_connection_class).to receive(:new).and_return(cable_connection_instance)

          router.process_connection(nil, env)
        end
      end

      context "with ApplicationCable::Connection in namespace" do
        let(:app_cable_connection_class) { Class.new(Rage::Cable::Connection) }

        before do
          app_cable_module = Module.new
          app_cable_module.const_set(:Connection, app_cable_connection_class)
          custom_namespace.const_set(:ApplicationCable, app_cable_module)
        end

        after do
          custom_namespace.send(:remove_const, :ApplicationCable) if custom_namespace.const_defined?(:ApplicationCable)
        end

        it "uses the namespaced ApplicationCable connection class" do
          router = described_class.new(nil, custom_namespace)
          cable_connection_instance = double(__connect: nil, rejected?: false, __identified_by_map: {})
          expect(app_cable_connection_class).to receive(:new).and_return(cable_connection_instance)

          router.process_connection(nil, env)
        end
      end

      context "with no connection class in namespace" do
        it "falls back to default Rage::Cable::Connection" do
          expect {
            described_class.new(nil, custom_namespace)
          }.to output(/WARNING: Could not find the RageCable connection class/).to_stdout
        end
      end
    end

    describe "#reset with namespace" do
      let(:protocol) { double(supports_rpc?: true) }

      it "clears the channels map on reset" do
        # Use a real constant for the namespace so reset can find it
        reset_namespace = Module.new
        stub_const("ResetTestNamespace", reset_namespace)

        channel_class = Class.new(Rage::Cable::Channel)
        stub_const("ResetTestNamespace::ResetTestChannel", channel_class)

        env["rage.cable"] = {}
        env["rage.identified_by"] = {}

        router = described_class.new(protocol, ResetTestNamespace)

        # Subscribe to cache the channel
        router.process_subscription(connection, env, :test_identifier, "ResetTestChannel", {})

        # Reset the router
        router.reset

        # The channel should be re-registered on next subscription
        expect(channel_class).to receive(:__register_actions).with(protocol).and_call_original
        router.process_subscription(connection, env, :test_identifier2, "ResetTestChannel", {})
      end

      it "re-initializes the connection class on reset" do
        reset_namespace = Module.new
        stub_const("ResetConnNamespace", reset_namespace)

        connection_class = Class.new(Rage::Cable::Connection)
        rage_cable_module = Module.new
        stub_const("ResetConnNamespace::RageCable", rage_cable_module)
        stub_const("ResetConnNamespace::RageCable::Connection", connection_class)

        env["rage.cable"] = {}
        env["rage.identified_by"] = {}

        router = described_class.new(protocol, ResetConnNamespace)

        # Verify initial connection class is used
        cable_connection_instance = double(__connect: nil, rejected?: false, __identified_by_map: {})
        expect(connection_class).to receive(:new).and_return(cable_connection_instance)
        router.process_connection(nil, env)

        # Create a new connection class and replace the old one
        new_connection_class = Class.new(Rage::Cable::Connection)
        ResetConnNamespace::RageCable.send(:remove_const, :Connection)
        ResetConnNamespace::RageCable.const_set(:Connection, new_connection_class)

        router.reset

        # After reset, the new connection class should be used
        new_cable_connection_instance = double(__connect: nil, rejected?: false, __identified_by_map: {})
        expect(new_connection_class).to receive(:new).and_return(new_cable_connection_instance)

        router.process_connection(nil, env)
      end

      it "handles anonymous namespaces without name" do
        anonymous_namespace = Module.new
        # Anonymous modules have name = nil

        env["rage.cable"] = {}
        env["rage.identified_by"] = {}

        channel_class = Class.new(Rage::Cable::Channel)
        anonymous_namespace.const_set(:TestChannel, channel_class)

        router = described_class.new(protocol, anonymous_namespace)

        # Reset should not raise for anonymous namespace
        expect { router.reset }.not_to raise_error
      end
    end
  end
end

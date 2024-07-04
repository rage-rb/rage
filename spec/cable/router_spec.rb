# frozen_string_literal: true

RSpec.describe Rage::Cable::Router do
  let(:connection) { instance_double("Iodine::Connection", env: {}) }

  before do
    allow(Rage).to receive_message_chain(:logger, :debug) do |&block|
      puts(block.call)
    end
  end

  describe "#process_connection" do
    subject { described_class.new.process_connection(connection) }

    let(:cable_connection_class) { double }
    let(:cable_connection_instance) { double(connect: nil, __identified_by_map: :test_identified_by) }

    before do
      stub_const("RageCable::Connection", cable_connection_class)
      allow(cable_connection_class).to receive(:method_defined?).with(:disconnect).and_return(true)
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
        expect(connection.env["rage.identified_by"]).to eq(:test_identified_by)
        expect(connection.env["rage.cable"]).to eq({})
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
        expect(connection.env).to be_empty
      end
    end
  end

  describe "#process_subscription" do
    subject { described_class.new.process_subscription(connection, :test_identifier, channel_name, :test_params) }

    let(:channel_name) { "TestChannel" }
    let(:cable_channel_class) { double }
    let(:channel) { instance_double("Rage::Cable::Channel") }

    context "with correct channel name" do
      before do
        stub_const(channel_name, cable_channel_class)
        allow(cable_channel_class).to receive(:ancestors).and_return([Rage::Cable::Channel])

        connection.env["rage.cable"] = {}
        connection.env["rage.identified_by"] = :test_identified_by
      end

      it "accepts the subscription" do
        expect(cable_channel_class).to receive(:__register_actions).once
        expect(cable_channel_class).to receive(:new).with(connection, :test_params, :test_identified_by).and_return(channel)

        expect(channel).to receive(:__run_action).with(:subscribed)
        expect(channel).to receive(:subscription_rejected?).and_return(false)

        expect(subject).to eq(:subscribed)
        expect(connection.env["rage.cable"][:test_identifier]).to eq(channel)
      end

      context "with rejection" do
        it "rejects the subscription" do
          expect(cable_channel_class).to receive(:__register_actions).once
          expect(cable_channel_class).to receive(:new).with(connection, :test_params, :test_identified_by).and_return(channel)

          expect(channel).to receive(:__run_action).with(:subscribed)
          expect(channel).to receive(:subscription_rejected?).and_return(true)

          expect(subject).to eq(:rejected)
          expect(connection.env["rage.cable"]).to be_empty
        end
      end
    end

    context "with incorrect channel name" do
      let(:channel_name) { "Array" }

      it "rejects the subscription" do
        expect(subject).to eq(:invalid)
        expect(connection.env).to be_empty
      end
    end

    context "with incorrect constant name" do
      let(:channel_name) { ";;;;;;;" }

      it "rejects the subscription" do
        expect(subject).to eq(:invalid)
        expect(connection.env).to be_empty
      end
    end
  end

  describe "#process_message" do
    subject { described_class.new.process_message(connection, :test_identifier, :test_action, :test_data) }

    context "with existing subscription" do
      let(:channel) { double }

      before do
        connection.env["rage.cable"] = { test_identifier: channel }
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
        connection.env["rage.cable"] = {}
      end

      it "discards the message" do
        expect(subject).to eq(:no_subscription)
      end
    end
  end

  describe "#process_disconnection" do
    subject { described_class.new.process_disconnection(connection) }

    context "with existing subscription" do
      let(:channel) { double }

      before do
        connection.env["rage.cable"] = { test_identifier: channel }
      end

      it "runs the unsubscribed callback" do
        expect(channel).to receive(:__run_action).with(:unsubscribed)
        subject
      end
    end

    context "with no subscription" do
      before do
        connection.env["rage.cable"] = nil
      end

      it "runs successfully" do
        expect { subject }.not_to raise_error
      end
    end

    context "with connection" do
      let(:cable_connection_class) { double }
      let(:cable_connection_instance) { double(connect: nil, __identified_by_map: :test_identified_by) }

      before do
        stub_const("RageCable::Connection", cable_connection_class)
        allow(cable_connection_class).to receive(:method_defined?).with(:disconnect).and_return(true)
        allow(cable_connection_class).to receive(:new).and_return(cable_connection_instance)
      end

      it "calls disconnect on the connection class" do
        expect(cable_connection_instance).to receive(:disconnect).once
        subject
      end
    end
  end
end

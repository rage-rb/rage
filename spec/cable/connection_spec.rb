# frozen_string_literal: true

require "domain_name"

RSpec.describe Rage::Cable::Connection do
  describe ".identified_by" do
    subject { described_class.new(nil) }

    it "defines accessor methods" do
      described_class.identified_by(:test_user)

      expect(subject.test_user).to be_nil
      subject.test_user = :user
      expect(subject.test_user).to eq(:user)
    end

    it "defines channel methods" do
      expect(Rage::Cable::Channel).to receive(:__prepare_id_method).with(:test_user).once
      described_class.identified_by(:test_user)
    end

    context "with identified_by data" do
      subject { described_class.new(nil, { test_user: :user_2 }) }

      it "allows to access the data" do
        described_class.identified_by(:test_user)
        expect(subject.test_user).to eq(:user_2)
      end
    end
  end

  describe "#request" do
    subject { described_class.new({ "HTTP_SEC_WEBSOCKET_PROTOCOL" => "test-protocol" }) }

    it "correctly initializes the request object" do
      expect(subject.request).to be_a(Rage::Request)
      expect(subject.request.headers["Sec-Websocket-Protocol"]).to eq("test-protocol")
    end
  end

  describe "#cookies" do
    subject { described_class.new({ "HTTP_COOKIE" => "user_id=test-user-id" }) }

    it "correctly initializes the cookies object" do
      expect(subject.cookies).to be_a(Rage::Cookies)
      expect(subject.cookies[:user_id]).to eq("test-user-id")
    end

    it "doesn't allow to update cookies" do
      expect { subject.cookies[:user_id] = 111 }.to raise_error(/cannot be set/)
    end
  end

  describe "#params" do
    subject { described_class.new({ "QUERY_STRING" => "user_id=test-user-id" }) }

    it "correctly parses parameters" do
      expect(subject.params).to be_a(Hash)
      expect(subject.params[:user_id]).to eq("test-user-id")
    end
  end

  describe "#__connect" do
    let(:cable_connection_class) { Class.new(described_class) }
    let(:env) { double }
    let(:cable_connection) { cable_connection_class.new(env) }

    let(:connection) { double }
    let(:protocol) { double }

    subject { cable_connection.__connect(connection, protocol) }

    it "calls #connect" do
      expect(cable_connection).to receive(:connect)
      subject
    end

    it "doesn't set up RemoteDisconnect" do
      expect(cable_connection).not_to receive(:__remote_disconnect_setup)
      subject
    end

    context "with RemoteDisconnect" do
      let(:cable_connection_class) do
        Class.new(described_class) do
          include Rage::Cable::RemoteDisconnect
        end
      end

      it "calls #connect" do
        expect(cable_connection).to receive(:connect)
        subject
      end

      it "sets up RemoteDisconnect" do
        expect(cable_connection).to receive(:__remote_disconnect_setup).with(connection, protocol)
        subject
      end

      context "when rejected" do
        before do
          cable_connection.reject_unauthorized_connection
        end

        it "skips setting up RemoteDisconnect" do
          expect(cable_connection).not_to receive(:__remote_disconnect_setup)
          subject
        end
      end
    end
  end

  describe "#__disconnect" do
    let(:cable_connection_class) { Class.new(described_class) }
    let(:env) { double }
    let(:cable_connection) { cable_connection_class.new(env) }

    let(:connection) { double }

    subject { cable_connection.__disconnect(connection) }

    it "calls #disconnect" do
      expect(cable_connection).to receive(:disconnect)
      subject
    end

    it "doesn't clean up RemoteDisconnect" do
      expect(cable_connection).not_to receive(:__remote_disconnect_cleanup)
      subject
    end

    context "with RemoteDisconnect" do
      let(:cable_connection_class) do
        Class.new(described_class) do
          include Rage::Cable::RemoteDisconnect
        end
      end

      it "calls #disconnect" do
        expect(cable_connection).to receive(:disconnect)
        subject
      end

      it "cleans up RemoteDisconnect" do
        expect(cable_connection).to receive(:__remote_disconnect_cleanup).with(connection)
        subject
      end

      context "when rejected" do
        before do
          cable_connection.reject_unauthorized_connection
        end

        it "cleans up RemoteDisconnect" do
          expect(cable_connection).to receive(:__remote_disconnect_cleanup).with(connection)
          subject
        end
      end
    end
  end

  describe "RemoteDisconnect" do
    context ".disconnect" do
      context "with no identifiers" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect
          end
        end

        it "raises ArgumentError" do
          expect {
            cable_connection_class.disconnect(current_user: double)
          }.to raise_error(ArgumentError, /Unknown identifier/)
        end
      end

      context "with set identifier" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect

            identified_by :current_user
          end
        end

        before do
          stub_const("TestCableConnection", cable_connection_class)
        end

        it "raises ArgumentError on invalid identifier" do
          expect {
            cable_connection_class.disconnect(current_account: double)
          }.to raise_error(ArgumentError, /Unknown identifier: current_account/)
        end

        it "raises ArgumentError on multiple identifiers" do
          expect {
            cable_connection_class.disconnect(current_user: double, current_account: double)
          }.to raise_error(ArgumentError, /one identifier/)
        end

        it "raises ArgumentError on no identifiers" do
          expect {
            cable_connection_class.disconnect
          }.to raise_error(ArgumentError, /must be provided/)
        end

        it "publishes to a topic" do
          user = double(id: 1234)

          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_user, user]
          ]
          expect(Rage::PubSub).to receive(:publish).with(anything, topic: expected_topic)

          cable_connection_class.disconnect(current_user: user)
        end
      end

      context "with multiple identifiers" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect

            identified_by :current_user, :current_device
          end
        end

        before do
          stub_const("TestCableConnection", cable_connection_class)
        end

        it "raises ArgumentError on invalid identifier" do
          expect {
            cable_connection_class.disconnect(current_account: double)
          }.to raise_error(ArgumentError, /Unknown identifier: current_account/)
        end

        it "raises ArgumentError on multiple identifiers" do
          expect {
            cable_connection_class.disconnect(current_user: double, current_device: double)
          }.to raise_error(ArgumentError, /one identifier/)
        end

        it "publishes to a topic" do
          device = double(id: 1234)

          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_device, device]
          ]
          expect(Rage::PubSub).to receive(:publish).with(anything, topic: expected_topic)

          cable_connection_class.disconnect(current_device: device)
        end
      end
    end

    context "#__connect" do
      let(:cable_connection_class) do
        Class.new(described_class) do
          include Rage::Cable::RemoteDisconnect

          identified_by :current_user

          def connect
            self.current_user = :test_user
          end
        end
      end

      let(:connection) { double }
      let(:protocol) { double }
      let(:env) { double }
      let(:cable_connection) { cable_connection_class.new(env) }

      subject { cable_connection.__connect(connection, protocol) }

      before do
        stub_const("TestCableConnection", cable_connection_class)
      end

      it "subscribes to a topic" do
        expected_topic = [
          "rage",
          "TestCableConnection",
          [:current_user, :test_user]
        ]
        expect(Rage::PubSub).to receive(:subscribe).with(topic: expected_topic, subscription_id: connection)

        subject
      end

      it "creates a pub/sub callback" do
        pubsub_callback = nil
        allow(Rage::PubSub).to receive(:subscribe) do |&block|
          pubsub_callback = block
        end

        subject

        expect(protocol).to receive(:on_server_disconnect).with(connection)
        expect(connection).to receive(:close)

        pubsub_callback.call
      end

      context "with multiple identifiers" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect

            identified_by :current_user, :current_device

            def connect
              self.current_user = :test_user
              self.current_device = :test_device
            end
          end
        end

        it "subscribes to topics" do
          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_user, :test_user]
          ]
          expect(Rage::PubSub).to receive(:subscribe).with(topic: expected_topic, subscription_id: connection)

          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_device, :test_device]
          ]
          expect(Rage::PubSub).to receive(:subscribe).with(topic: expected_topic, subscription_id: connection)

          subject
        end
      end

      context "with no identifiers" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect
          end
        end

        it "doesn't subscribe" do
          expect(Rage::PubSub).not_to receive(:subscribe)
          subject
        end
      end

      context "with identifiers passed to constructor" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect
          end
        end

        let(:current_account) { double }
        let(:current_location) { double }
        let(:cable_connection) { cable_connection_class.new(env, { current_account:, current_location: }) }

        before do
          stub_const("TestCableConnection", cable_connection_class)
        end

        it "subscribes to topics" do
          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_account, current_account]
          ]
          expect(Rage::PubSub).to receive(:subscribe).with(topic: expected_topic, subscription_id: connection)

          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_location, current_location]
          ]
          expect(Rage::PubSub).to receive(:subscribe).with(topic: expected_topic, subscription_id: connection)

          subject
        end
      end
    end

    context "#__disconnect" do
      let(:cable_connection_class) do
        Class.new(described_class) do
          include Rage::Cable::RemoteDisconnect

          identified_by :current_user

          def connect
            self.current_user = :test_user
          end
        end
      end

      let(:connection) { double }
      let(:env) { double }
      let(:cable_connection) { cable_connection_class.new(env) }

      subject { cable_connection.__disconnect(connection) }

      before do
        stub_const("TestCableConnection", cable_connection_class)
      end

      it "unsubscribes from a topic" do
        expected_topic = [
          "rage",
          "TestCableConnection",
          [:current_user, :test_user]
        ]
        expect(Rage::PubSub).to receive(:unsubscribe).with(topic: expected_topic, subscription_id: connection)

        cable_connection.connect
        subject
      end

      context "with multiple topics" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect

            identified_by :current_user, :current_device

            def connect
              self.current_user = :test_user
              self.current_device = :test_device
            end
          end
        end

        it "unsubscribes from all topics" do
          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_user, :test_user]
          ]
          expect(Rage::PubSub).to receive(:unsubscribe).with(topic: expected_topic, subscription_id: connection)

          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_device, :test_device]
          ]
          expect(Rage::PubSub).to receive(:unsubscribe).with(topic: expected_topic, subscription_id: connection)

          cable_connection.connect
          subject
        end
      end

      context "with no identifiers" do
        let(:cable_connection_class) do
          Class.new(described_class) do
            include Rage::Cable::RemoteDisconnect
          end
        end

        it "doesn't unsubscribe" do
          expect(Rage::PubSub).not_to receive(:unsubscribe)

          cable_connection.connect
          subject
        end
      end

      context "with identifiers passed to constructor" do
        let(:current_user) { double }
        let(:cable_connection) { cable_connection_class.new(env, { current_user: }) }

        it "unsubscribes from the topic" do
          expected_topic = [
            "rage",
            "TestCableConnection",
            [:current_user, current_user]
          ]
          expect(Rage::PubSub).to receive(:unsubscribe).with(topic: expected_topic, subscription_id: connection)

          subject
        end

        context "with nil identifiers" do
          let(:cable_connection) { cable_connection_class.new(env, nil) }

          it "doesn't unsubscribe" do
            expect(Rage::PubSub).not_to receive(:unsubscribe)
            expect { subject }.not_to raise_error
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module CableChannelStreamForSpec
  class TestChannel < Rage::Cable::Channel
    def subscribed
      stream_for params[:user]
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    def subscribed
      stream_for "global"
    end
  end

  class User
    attr_reader :id

    def initialize(id)
      @id = id
    end
  end
end

RSpec.describe Rage::Cable::Channel do
  let(:protocol) { double("protocol", supports_rpc?: true) }
  let(:connection) { double("connection") }
  let(:params) { {} }
  let(:identified_by) { {} }

  before do
    allow(Rage.cable).to receive(:__protocol).and_return(protocol)
    allow(Rage.cable).to receive(:broadcast)
  end

  describe "#stream_for" do
    subject { klass.tap(&:__register_actions).new(connection, params, identified_by) }

    context "with an object that responds to id" do
      let(:klass) { CableChannelStreamForSpec::TestChannel }
      let(:user) { CableChannelStreamForSpec::User.new(123) }
      let(:params) { { user: user } }

      it "subscribes to a stream with the channel name and object id" do
        expect(protocol).to receive(:subscribe).with(
          connection,
          "CableChannelStreamForSpec::TestChannel:CableChannelStreamForSpec::User:123",
          params
        )
        subject.__run_action(:subscribed)
      end
    end

    context "with a string streamable" do
      let(:klass) { CableChannelStreamForSpec::TestChannel2 }

      it "subscribes to a stream with the channel name and string" do
        expect(protocol).to receive(:subscribe).with(
          connection,
          "CableChannelStreamForSpec::TestChannel2:global",
          params
        )
        subject.__run_action(:subscribed)
      end
    end

    context "with a symbol streamable" do
      let(:klass) { CableChannelStreamForSpec::TestChannel }
      let(:params) { { user: :admin } }

      it "subscribes to a stream with the channel name and symbol" do
        expect(protocol).to receive(:subscribe).with(
          connection,
          "CableChannelStreamForSpec::TestChannel:admin",
          params
        )
        subject.__run_action(:subscribed)
      end
    end

    context "with a numeric streamable" do
      let(:klass) { CableChannelStreamForSpec::TestChannel }
      let(:params) { { user: 42 } }

      it "subscribes to a stream with the channel name and number" do
        expect(protocol).to receive(:subscribe).with(
          connection,
          "CableChannelStreamForSpec::TestChannel:42",
          params
        )
        subject.__run_action(:subscribed)
      end
    end

    context "with an array of streamables" do
      let(:klass) { CableChannelStreamForSpec::TestChannel }
      let(:user) { CableChannelStreamForSpec::User.new(123) }
      let(:params) { { user: [user, "room", 456] } }

      it "subscribes to a stream with the channel name and joined stream parts" do
        expect(protocol).to receive(:subscribe).with(
          connection,
          "CableChannelStreamForSpec::TestChannel:CableChannelStreamForSpec::User:123:room:456",
          params
        )
        subject.__run_action(:subscribed)
      end
    end

    context "with an invalid streamable" do
      let(:klass) { CableChannelStreamForSpec::TestChannel }
      let(:params) { { user: Object.new } }

      it "raises an ArgumentError" do
        allow(protocol).to receive(:subscribe)
        expect { subject.__run_action(:subscribed) }.to raise_error(
          ArgumentError,
          /Unable to generate stream name/
        )
      end
    end
  end

  describe ".broadcast_to" do
    context "with an object that responds to id" do
      let(:user) { CableChannelStreamForSpec::User.new(123) }

      it "broadcasts to the correct stream" do
        expect(Rage.cable).to receive(:broadcast).with(
          "CableChannelStreamForSpec::TestChannel:CableChannelStreamForSpec::User:123",
          { message: "Hello!" }
        )
        CableChannelStreamForSpec::TestChannel.broadcast_to(user, { message: "Hello!" })
      end
    end

    context "with a string streamable" do
      it "broadcasts to the correct stream" do
        expect(Rage.cable).to receive(:broadcast).with(
          "CableChannelStreamForSpec::TestChannel:notifications",
          { type: "alert" }
        )
        CableChannelStreamForSpec::TestChannel.broadcast_to("notifications", { type: "alert" })
      end
    end

    context "with a symbol streamable" do
      it "broadcasts to the correct stream" do
        expect(Rage.cable).to receive(:broadcast).with(
          "CableChannelStreamForSpec::TestChannel:admin",
          { data: 123 }
        )
        CableChannelStreamForSpec::TestChannel.broadcast_to(:admin, { data: 123 })
      end
    end

    context "with a numeric streamable" do
      it "broadcasts to the correct stream" do
        expect(Rage.cable).to receive(:broadcast).with(
          "CableChannelStreamForSpec::TestChannel:42",
          { count: 1 }
        )
        CableChannelStreamForSpec::TestChannel.broadcast_to(42, { count: 1 })
      end
    end

    context "with an array of streamables" do
      let(:user) { CableChannelStreamForSpec::User.new(123) }

      it "broadcasts to the correct stream" do
        expect(Rage.cable).to receive(:broadcast).with(
          "CableChannelStreamForSpec::TestChannel:CableChannelStreamForSpec::User:123:room:456",
          { message: "Hello!" }
        )
        CableChannelStreamForSpec::TestChannel.broadcast_to([user, "room", 456], { message: "Hello!" })
      end
    end

    context "with an invalid streamable" do
      it "raises an ArgumentError" do
        expect {
          CableChannelStreamForSpec::TestChannel.broadcast_to(Object.new, { message: "Hello!" })
        }.to raise_error(ArgumentError, /Unable to generate stream name/)
      end
    end
  end
end

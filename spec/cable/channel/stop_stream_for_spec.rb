# frozen_string_literal: true

module CableChannelStopStreamForSpec
  class TestChannel < Rage::Cable::Channel
    def subscribed
      stream_for params[:user]
    end

    def unfollow
      stop_stream_for params[:user]
    end
  end

  class TestChannel2 < Rage::Cable::Channel
    def subscribed
      stream_for "global"
    end

    def leave
      stop_stream_for "global"
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

  describe "#stop_stream_for" do
    subject { klass.tap(&:__register_actions).new(connection, params, identified_by) }

    context "with an object that responds to id" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel }
      let(:user) { CableChannelStopStreamForSpec::User.new(123) }
      let(:params) { { user: user } }

      it "unsubscribes from a stream with the channel name and object id" do
        allow(protocol).to receive(:subscribe)
        expect(protocol).to receive(:unsubscribe).with(
          connection,
          "CableChannelStopStreamForSpec::TestChannel:CableChannelStopStreamForSpec::User:123",
          params
        )
        subject.__run_action(:subscribed)
        subject.__run_action(:unfollow)
      end
    end

    context "with a string streamable" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel2 }

      it "unsubscribes from a stream with the channel name and string" do
        allow(protocol).to receive(:subscribe)
        expect(protocol).to receive(:unsubscribe).with(
          connection,
          "CableChannelStopStreamForSpec::TestChannel2:global",
          params
        )
        subject.__run_action(:subscribed)
        subject.__run_action(:leave)
      end
    end

    context "with a symbol streamable" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel }
      let(:params) { { user: :admin } }

      it "unsubscribes from a stream with the channel name and symbol" do
        allow(protocol).to receive(:subscribe)
        expect(protocol).to receive(:unsubscribe).with(
          connection,
          "CableChannelStopStreamForSpec::TestChannel:admin",
          params
        )
        subject.__run_action(:subscribed)
        subject.__run_action(:unfollow)
      end
    end

    context "with a numeric streamable" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel }
      let(:params) { { user: 42 } }

      it "unsubscribes from a stream with the channel name and number" do
        allow(protocol).to receive(:subscribe)
        expect(protocol).to receive(:unsubscribe).with(
          connection,
          "CableChannelStopStreamForSpec::TestChannel:42",
          params
        )
        subject.__run_action(:subscribed)
        subject.__run_action(:unfollow)
      end
    end

    context "with an array of streamables" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel }
      let(:user) { CableChannelStopStreamForSpec::User.new(123) }
      let(:params) { { user: [user, "room", 456] } }

      it "unsubscribes from a stream with the channel name and joined stream parts" do
        allow(protocol).to receive(:subscribe)
        expect(protocol).to receive(:unsubscribe).with(
          connection,
          "CableChannelStopStreamForSpec::TestChannel:CableChannelStopStreamForSpec::User:123:room:456",
          params
        )
        subject.__run_action(:subscribed)
        subject.__run_action(:unfollow)
      end
    end

    context "with an invalid streamable" do
      let(:klass) { CableChannelStopStreamForSpec::TestChannel }
      let(:params) { { user: Object.new } }

      it "raises an ArgumentError" do
        allow(protocol).to receive(:subscribe)
        allow(protocol).to receive(:unsubscribe)
        expect { subject.__run_action(:unfollow) }.to raise_error(
          ArgumentError,
          /Unable to generate stream name/
        )
      end
    end
  end
end

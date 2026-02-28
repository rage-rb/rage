# frozen_string_literal: true

module CableChannelStopStreamFromSpec
  class TestChannel < Rage::Cable::Channel
    def subscribed
      stream_from "test_stream"
    end

    def leave
      stop_stream_from "test_stream"
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
  end

  describe "#stop_stream_from" do
    subject { klass.tap(&:__register_actions).new(connection, params, identified_by) }

    let(:klass) { CableChannelStopStreamFromSpec::TestChannel }

    it "unsubscribes from the stream" do
      allow(protocol).to receive(:subscribe)
      expect(protocol).to receive(:unsubscribe).with(connection, "test_stream", params)
      subject.__run_action(:subscribed)
      subject.__run_action(:leave)
    end

    it "raises an ArgumentError if the stream name is not a String" do
      expect { subject.send(:stop_stream_from, 123) }.to raise_error(
        ArgumentError,
        "Stream name must be a String"
      )
    end

    it "raises an ArgumentError if the stream name is a Symbol" do
      expect { subject.send(:stop_stream_from, :test) }.to raise_error(
        ArgumentError,
        "Stream name must be a String"
      )
    end
  end
end

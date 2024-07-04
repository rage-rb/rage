# frozen_string_literal: true

module CableChannelIdentifiedBySpec
  class TestChannel < Rage::Cable::Channel
  end
end

RSpec.describe Rage::Cable::Channel do
  subject { CableChannelIdentifiedBySpec::TestChannel.new(nil, nil, identified_by) }

  let(:identified_by) { { current_user: :test_user, current_account: :test_account } }

  before do
    CableChannelIdentifiedBySpec::TestChannel.__prepare_id_method(:current_user)
    CableChannelIdentifiedBySpec::TestChannel.__prepare_id_method(:current_account)
  end

  it "correctly delegates identified_by methods" do
    expect(subject.current_user).to eq(:test_user)
    expect(subject.current_account).to eq(:test_account)
  end
end

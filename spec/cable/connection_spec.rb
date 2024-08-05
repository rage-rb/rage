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
end

# frozen_string_literal: true

require "rbnacl"
require "domain_name"

RSpec.describe RageController::API do
  subject { described_class.new(headers, nil) }

  let(:encoded_session) { "" }
  let(:headers) { { "HTTP_COOKIE" => "#{Rage::Session.key}=#{encoded_session}" } }

  before do
    allow(Rage.config).to receive(:secret_key_base).and_return("rage-test-key")
  end

  context "when reading a valid session" do
    let(:encoded_session) { "MDDTFjPTyaIdJjZG2C-RJmDPC_5fMyBMTn87Dv7EID3g-OJwakyxFQUhoSlxwqdLRw4npvm08F0=" }

    it "correctly reads values" do
      expect(subject.session[:a]).to eq(1)
      expect(subject.session[:b]).to eq(22)
      expect(subject.session[:c]).to be_nil
    end

    it "correctly fetches values" do
      expect(subject.session.fetch(:a)).to eq(1)
      expect(subject.session.fetch(:b, 33)).to eq(22)
      expect(subject.session.fetch(:c, 44)).to eq(44)
      expect { subject.session.fetch(:d) }.to raise_error(KeyError)
    end

    it "correctly converts to hash" do
      expect(subject.session.to_h).to eq({ a: 1, b: 22 })
    end

    it "correctly checks if the session is empty?" do
      expect(subject.session).not_to be_empty
    end

    it "correctly checks if a key is present in the session" do
      expect(subject.session.has_key?(:a)).to be(true)
      expect(subject.session.has_key?(:c)).to be(false)
    end

    it "correctly implements `dig`" do
      expect(subject.session.dig(:a)).to eq(1)
      expect(subject.session.dig(:c, :d)).to be_nil
    end
  end

  context "when reading an invalid session" do
    let(:encoded_session) { "MDDTFjPTyaIdJjZG2C-RJmDPC_5fMyBMT-OJwakyxFQUhoSlxwqdLRw4npvm08F0=" }

    before do
      allow(Rage).to receive(:logger).and_return(double(debug: nil))
    end

    it "correctly reads values" do
      expect(subject.session[:a]).to be_nil
    end

    it "correctly converts to hash" do
      expect(subject.session.to_h).to eq({})
    end

    it "correctly checks if the session is empty?" do
      expect(subject.session).to be_empty
    end
  end

  context "when reading an empty session" do
    let(:headers) { {} }

    it "correctly reads values" do
      expect(subject.session[:a]).to be_nil
    end

    it "correctly converts to hash" do
      expect(subject.session.to_h).to eq({})
    end

    it "correctly checks if the session is empty?" do
      expect(subject.session).to be_empty
    end
  end

  context "when writing a session" do
    let(:new_session) do
      _, session_cookie = subject.headers.find { |k, _| k == "Set-Cookie" }
      session_value = session_cookie.match(/#{Rage::Session.key}=(\S+);/)[1]

      Rage::Cookies::EncryptedJar.load(
        Rack::Utils.unescape(session_value, Encoding::UTF_8)
      )
    end

    before do
      allow(Rage).to receive(:logger).and_return(double(debug: nil))
    end

    it "correctly updates the session" do
      subject.session[:abc] = 123
      subject.session[:cde] = 456

      expect(new_session).to eq("{\"abc\":123,\"cde\":456}")
    end

    it "correctly deletes keys from the session" do
      subject.session[:abc] = 123
      subject.session[:cde] = 456
      subject.session.delete(:cde)

      expect(new_session).to eq("{\"abc\":123}")
    end

    it "correctly clears the session" do
      subject.session[:abc] = 123
      subject.session.clear

      expect(new_session).to eq("{}")
    end

    it "sets correct attributes" do
      subject.session[:abc] = 123
      _, session_cookie = subject.headers.find { |k, _| k == "Set-Cookie" }

      expect(session_cookie).to match(/.+; HttpOnly; SameSite=Lax/)
    end
  end

  context "when resetting a session" do
    it "calls clear" do
      expect(subject.session).to receive(:clear).once
      subject.reset_session
    end
  end

  context "with standard session key" do
    subject { Class.new(Rage::Session).key }

    before do
      allow(Rage).to receive(:root).and_return(double(basename: basename))
    end

    context "with valid name" do
      let(:basename) { "test" }

      it "builds correct key" do
        expect(subject).to eq(:_test_session)
      end
    end

    context "with spaces" do
      let(:basename) { "my test" }

      it "builds correct key" do
        expect(subject).to eq(:_my_test_session)
      end
    end

    context "with uppercase characters" do
      let(:basename) { "MY test" }

      it "builds correct key" do
        expect(subject).to eq(:_my_test_session)
      end
    end

    context "with special characters" do
      let(:basename) { "$ession+key=t est!" }

      it "builds correct key" do
        expect(subject).to eq(:__ession_key_t_est__session)
      end
    end
  end

  context "with custom session key" do
    subject { Class.new(Rage::Session).key }

    before do
      allow(Rage.config).to receive(:session).and_return(double(key: "custom_key"))
    end

    it "builds correct key" do
      expect(subject).to eq(:custom_key)
    end
  end
end

# frozen_string_literal: true

RSpec.describe RageController::API do
  subject { described_class.new(env, nil) }

  context "with a Bearer token" do
    let(:env) { { "HTTP_AUTHORIZATION" => "Bearer my_token" } }

    it "extracts the token" do
      subject.authenticate_with_http_token do |token|
        expect(token).to eq("my_token")
      end
    end

    it "returns the value of the login procedure" do
      value = subject.authenticate_with_http_token { :request_authenticated }
      expect(value).to eq(:request_authenticated)
    end
  end

  context "with a Token token" do
    let(:env) { { "HTTP_AUTHORIZATION" => "Token my_token" } }

    it "extracts the token" do
      subject.authenticate_with_http_token do |token|
        expect(token).to eq("my_token")
      end
    end

    it "returns the value of the login procedure" do
      value = subject.authenticate_with_http_token { :request_authenticated }
      expect(value).to eq(:request_authenticated)
    end
  end

  context "with a Digest token" do
    let(:env) { { "HTTP_AUTHORIZATION" => "Digest my_token" } }

    it "doesn't extract the token" do
      value = subject.authenticate_with_http_token { :request_authenticated }
      expect(value).to be_nil
    end

    it "doesn't call the login procedure" do
      expect {
        subject.authenticate_with_http_token { raise }
      }.not_to raise_error
    end
  end

  context "with no token" do
    let(:env) { {} }

    it "returns nil" do
      value = subject.authenticate_with_http_token { :request_authenticated }
      expect(value).to be_nil
    end

    it "doesn't call the login procedure" do
      expect {
        subject.authenticate_with_http_token { raise }
      }.not_to raise_error
    end
  end
end

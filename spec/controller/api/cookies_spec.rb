# frozen_string_literal: true

require "rbnacl"
require "domain_name"

RSpec.describe RageController::API do
  subject do
    cookie_header = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
    described_class.new({ "HTTP_COOKIE" => cookie_header, "HTTP_HOST" => "cookie.test.com" }, nil)
  end

  context "with no cookies" do
    let(:cookies) { {} }

    it "works correctly" do
      expect(subject.cookies.size).to eq(0)
      expect(subject.cookies[:test_key]).to be_nil
      expect(subject.cookies.encrypted[:encrypted_test_key]).to be_nil
    end
  end

  context "with cookies" do
    before do
      allow(Rage.config).to receive(:secret_key_base).and_return("rage-test-key")
      allow(Rage.config).to receive(:fallback_secret_key_base).and_return(%w(rage-fallback-key))
    end

    let(:cookies) do
      {
        user_id: 112,
        callback_url: "https://test-host.com",
        session: "MDB4tHk-Qm-da9_zeXE8NaywvyzidycD4qIhK1xWmYVJE_jYeuo_rzd9Eb6gwCLBn8eYaqT9QBomfAFA"
      }
    end

    it "correctly deserializes cookies" do
      expect(subject.cookies.size).to eq(3)
      expect(subject.cookies[:user_id]).to eq("112")
      expect(subject.cookies[:callback_url]).to eq("https://test-host.com")
      expect(subject.cookies.encrypted[:session]).to eq("primary-test-value")
    end

    it "correctly updates local state" do
      subject.cookies[:user_id] = 555
      expect(subject.cookies.size).to eq(3)

      subject.cookies.delete(:callback_url)
      expect(subject.cookies.size).to eq(2)

      subject.cookies[:account_id] = 77
      expect(subject.cookies.size).to eq(3)

      subject.cookies.encrypted[:auth] = "test"
      expect(subject.cookies.size).to eq(4)

      expect(subject.cookies[:user_id]).to eq("555")
      expect(subject.cookies[:callback_url]).to be_nil
      expect(subject.cookies[:account_id]).to eq("77")

      expect(subject.cookies[:auth]).not_to be_empty
      expect(subject.cookies[:auth]).not_to eq("test")
      expect(subject.cookies.encrypted[:auth]).to eq("test")
    end

    it "correctly updates local state" do
      subject.cookies.delete(:user_id)

      expect(subject.cookies.size).to eq(2)
      expect(subject.cookies[:user_id]).to be_nil
    end

    context "with data encrypted with rotated key" do
      let(:cookies) do
        { session: "MDC9exZmtbHuQ0hKQbfuf69gBQE0oER1y0DInAq686395nMYPVRxt0D3W8wt0jjegw1LNu4MSvQf1LSWdw==" }
      end

      it "correctly decrypts data" do
        expect(subject.cookies.encrypted[:session]).to eq("fallback-test-value")
      end
    end

    context "with incorrectly encrypted data" do
      let(:cookies) { { session: "MDC9exZmtbHuQ0hK" } }

      it "return nil" do
        expect(subject.cookies.encrypted[:session]).to be_nil
      end
    end

    context "with incorrectly base64 encoded data" do
      let(:cookies) { { session: ";;;;;;;" } }

      it "return nil" do
        expect(subject.cookies.encrypted[:session]).to be_nil
      end
    end

    context "with decoded data" do
      let(:cookies) { { data: "---%0A%3Aaccount_id%3A+10%0A" } }

      it "correctly decodes data" do
        expect(subject.cookies[:data]).to eq("---\n:account_id: 10\n")
      end
    end
  end

  context "when setting cookies" do
    let(:cookies) { [] }
    let(:response_cookies) do
      subject.headers.each_with_object({}) do |(header, value), memo|
        if header == "Set-Cookie"
          k, v = value.split("=", 2)
          memo[k.to_sym] = v
        end
      end
    end

    it "correctly sets string values" do
      subject.cookies[:user_id] = 100

      expect(response_cookies.size).to eq(1)
      expect(response_cookies[:user_id]).to eq("100")
    end

    it "correctly sets hash values" do
      subject.cookies[:user_id] = { value: 100 }
      expect(response_cookies[:user_id]).to eq("100")
    end

    it "correctly sets hash values" do
      subject.cookies[:user_id] = {
        path: "/users",
        secure: true,
        httponly: true,
        same_site: :lax,
        value: 110
      }

      expect(response_cookies[:user_id]).to eq("110; path=/users; secure; HttpOnly; SameSite=Lax")
    end

    it "correctly sets multiple values" do
      subject.cookies[:user_id] = 1
      subject.cookies[:account_id] = 2
      subject.cookies[:session_id] = 3

      expect(response_cookies.size).to eq(3)
      expect(response_cookies[:user_id]).to eq("1")
      expect(response_cookies[:account_id]).to eq("2")
      expect(response_cookies[:session_id]).to eq("3")
    end

    it "escapes data" do
      subject.cookies[:data] = { user_id: 1, account_id: "2" }.to_json
      expect(response_cookies[:data]).to eq("%7B%22user_id%22%3A1%2C%22account_id%22%3A%222%22%7D")
    end

    it "reuses the same Set-Cookie key" do
      subject.cookies[:user_id] = 100
      subject.cookies.delete(:user_id)
      subject.cookies[:user_id] = 200

      expect(subject.headers.count { |k, _| k == "Set-Cookie" }).to eq(1)
    end

    context "with string domain" do
      it "correctly sets domain value" do
        subject.cookies[:user_id] = {
          domain: "test.com",
          value: 120
        }

        expect(response_cookies[:user_id]).to eq("120; domain=test.com")
      end
    end

    context "with array domain" do
      it "correctly sets domain value" do
        subject.cookies[:user_id] = {
          domain: %w(api.test.com cookie.test.com),
          value: 120
        }

        expect(response_cookies[:user_id]).to eq("120; domain=cookie.test.com")
      end
    end

    context "with :all domain" do
      it "correctly sets domain value" do
        subject.cookies[:user_id] = {
          domain: :all,
          value: 120
        }

        expect(response_cookies[:user_id]).to eq("120; domain=test.com")
      end
    end

    context "with permanent cookies" do
      it "correctly sets permanent cookies" do
        subject.cookies.permanent[:user_id] = 333
        expect(response_cookies[:user_id]).to match(/333; expires=\w{3}, \d{2} \w{3} #{Time.now.year + 20} \d{2}:\d{2}:\d{2} GMT/)
      end

      it "correctly sets permanent cookies with hash values" do
        subject.cookies.permanent[:user_id] = { value: 444 }
        expect(response_cookies[:user_id]).to match(/444; expires=\w{3}, \d{2} \w{3} #{Time.now.year + 20} \d{2}:\d{2}:\d{2} GMT/)
      end

      it "correctly sets permanent cookies with encrypted values" do
        allow(Rage.config).to receive(:secret_key_base).and_return("rage-test-key")

        subject.cookies.encrypted.permanent[:user_id] = "secret"
        expect(response_cookies[:user_id]).to match(/\S+; expires=\w{3}, \d{2} \w{3} #{Time.now.year + 20} \d{2}:\d{2}:\d{2} GMT/)
      end

      it "doesn't override expiration date" do
        subject.cookies.permanent[:user_id] = { value: 444, expires: Time.now }
        expect(response_cookies[:user_id]).to match(/444; expires=\w{3}, \d{2} \w{3} #{Time.now.year} \d{2}:\d{2}:\d{2} GMT/)
      end

      it "resets expiration flag" do
        subject.cookies.permanent[:user_id] = 555
        subject.cookies[:account_id] = 2

        expect(response_cookies[:account_id]).to eq("2")
      end
    end
  end
end

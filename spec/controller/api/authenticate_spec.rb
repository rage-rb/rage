# frozen_string_literal: true

RSpec.describe RageController::API do
  subject { described_class.new(env, nil) }

  context "#authenticate_with_http_token" do
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

      context "with a token prefix" do
        let(:env) { { "HTTP_AUTHORIZATION" => "Bearer token=my_token" } }

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

      context "with a token prefix" do
        let(:env) { { "HTTP_AUTHORIZATION" => "Token token=my_token" } }

        it "extracts the token" do
          subject.authenticate_with_http_token do |token|
            expect(token).to eq("my_token")
          end
        end

        it "returns the value of the login procedure" do
          value = subject.authenticate_with_http_token { :request_authenticated }
          expect(value).to eq(:request_authenticated)
        end

        context "with quotes" do
          let(:env) { { "HTTP_AUTHORIZATION" => "Token token=\"my_token\"" } }

          it "extracts the token" do
            subject.authenticate_with_http_token do |token|
              expect(token).to eq("my_token")
            end
          end
        end
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

  context "#authenticate_or_request_with_http_token" do
    let(:env) { {} }

    before do
      expect(subject).to receive(:authenticate_with_http_token).and_yield("my_test_token")
    end

    it "extracts the token" do
      subject.authenticate_or_request_with_http_token do |token|
        expect(token).to eq("my_test_token")
      end
    end

    it "returns the value of the login procedure" do
      value = subject.authenticate_or_request_with_http_token { :request_authenticated }
      expect(value).to eq(:request_authenticated)
    end

    it "doesn't request authentication if login procedure returns non nil" do
      subject.authenticate_or_request_with_http_token { :request_authenticated }
      expect(subject.response.headers).not_to have_key("Www-Authenticate")
    end

    it "doesn't request authentication if login procedure returns nil" do
      subject.authenticate_or_request_with_http_token {}
      expect(subject.response.headers["Www-Authenticate"]).to eq("Token")
    end
  end

  context "#request_http_token_authentication" do
    let(:env) { {} }

    it "requests token authentication" do
      subject.request_http_token_authentication {}

      expect(subject.response.body).to eq("HTTP Token: Access denied.")
      expect(subject.response.headers["Www-Authenticate"]).to eq("Token")
    end
  end
end

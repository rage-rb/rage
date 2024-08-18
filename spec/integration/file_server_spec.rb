# frozen_string_literal: true

require "http"

RSpec.describe "File server" do
  before :all do
    skip("skipping file server tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  subject { http.get(url) }
  let(:http) { HTTP }
  let(:url) { "http://localhost:3000/test.txt" }

  context "with file server disabled" do
    before :all do
      launch_server
    end

    after :all do
      stop_server
    end

    it "doesn't allow to access public assets" do
      expect(subject.code).to eq(404)
    end
  end

  context "with file server enabled" do
    before :all do
      launch_server(env: { "ENABLE_FILE_SERVER" => "1" })
    end

    after :all do
      stop_server
    end

    it "allows to access public assets" do
      expect(subject.code).to eq(200)
      expect(subject.to_s).to eq("ABCDEFGHIJKLMNOPQRSTUVWXYZ\n")
    end

    it "returns correct headers" do
      expect(subject.headers["content-length"]).to eq("27")
      expect(subject.headers["content-type"]).to eq("text/plain")
      expect(subject.headers["etag"]).not_to be_empty
      expect(subject.headers["last-modified"]).not_to be_empty
    end

    it "fallbacks to application routes" do
      response = HTTP.get("http://localhost:3000/get")
      expect(response.code).to eq(200)
      expect(response.to_s).to eq("i am a get response")
    end

    context "with valid range" do
      let(:http) { HTTP.headers(range: "bytes=5-9") }

      it "returns correct response" do
        expect(subject.code).to eq(206)
        expect(subject.to_s).to eq("FGHIJ")
      end

      it "returns correct headers" do
        expect(subject.headers["content-length"]).to eq("5")
        expect(subject.headers["content-range"]).to eq("bytes 5-9/27")
      end
    end

    context "with invalid range" do
      let(:http) { HTTP.headers(range: "bytes=5-100") }

      it "returns correct response" do
        expect(subject.code).to eq(416)
      end

      it "returns correct headers" do
        expect(subject.headers["content-range"]).to eq("bytes */27")
      end
    end

    context "with If-None-Match" do
      let(:http) { HTTP.headers(if_none_match: etag) }

      context "with valid etag" do
        let(:etag) { HTTP.get(url).headers["etag"] }

        it "returns correct response" do
          expect(subject.code).to eq(304)
        end
      end

      context "with invalid etag" do
        let(:etag) { "invalid-etag" }

        it "returns correct response" do
          expect(subject.code).to eq(200)
          expect(subject.to_s).to eq("ABCDEFGHIJKLMNOPQRSTUVWXYZ\n")
        end
      end
    end

    context "with If-Range" do
      let(:http) { HTTP.headers(range: "bytes=5-9", if_range: etag) }

      context "with valid etag" do
        let(:etag) { HTTP.get(url).headers["etag"] }

        it "returns correct response" do
          expect(subject.code).to eq(206)
          expect(subject.to_s).to eq("FGHIJ")
        end
      end

      context "with invalid etag" do
        let(:etag) { "invalid-etag" }

        it "returns correct status code" do
          expect(subject.code).to eq(200)
          expect(subject.to_s).to eq("ABCDEFGHIJKLMNOPQRSTUVWXYZ\n")
        end
      end
    end

    context "with URL outside public directory" do
      let(:url) { "http://localhost:3000/../Gemfile" }

      it "returns correct status code" do
        expect(subject.code).to eq(404)
      end
    end
  end
end

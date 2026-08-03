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

    context "with shadowing an upgrade endpoint" do
      let(:url) { "http://localhost:3000/sse/stream" }

      before do
        FileUtils.mkdir_p("spec/integration/test_app/public/sse")
        File.write("spec/integration/test_app/public/sse/stream", "static stream file")
      end

      after do
        FileUtils.rm_r("spec/integration/test_app/public/sse")
      end

      it "returns correct response" do
        expect(subject.code).to eq(200)
        expect(subject.to_s).to eq("static stream file")
      end
    end

    context "with x-sendfile" do
      it "renders file" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/index.html.erb" })

        expect(response.code).to eq(200)
        expect(response.to_s).to eq("<p>index page</p>\n")
      end

      it "strips service headers" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/index.html.erb" })

        expect(response.headers).not_to include("x-sendfile")
        expect(response.headers).not_to include("x-sendfile-root")
      end

      it "allows to customize response headers" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/index.html.erb" })

        expect(response.headers["cache-control"]).to eq("max-age=604800")
        expect(response.headers["rage-custom-header"]).to eq("qwerty")
      end

      it "renders file from nested folder" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/pages/create.html.erb" })

        expect(response.code).to eq(200)
        expect(response.to_s).to eq("<p>create page</p>\n")
      end

      it "renders 404 for unknown files" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/unknown.html.erb" })

        expect(response.code).to eq(404)
      end

      it "strips custom headers for 404 responses" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/unknown.html.erb" })

        expect(response.headers["cache-control"]).to eq("no-cache, max-age=0")
        expect(response.headers).not_to include("rage-custom-header")
      end

      it "renders 404 for directories" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "/pages" })

        expect(response.code).to eq(404)
      end

      it "doesn't allow to access files outside x-sendfile-root" do
        response = HTTP.get("http://localhost:3000/static", params: { file: "../controllers/application_controller.rb" })

        expect(response.code).to eq(404)
        expect(response.to_s).to eq("404 Not Found")
      end
    end
  end
end

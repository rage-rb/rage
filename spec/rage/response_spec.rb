# frozen_string_literal: true

RSpec.describe Rage::Response do
  let(:headers) { {} }
  let(:body) { {} }

  subject { described_class.new(headers, body) }

  describe "cache headers" do
    let(:raw_cache_key) { "123-456" }
    let(:etag) { Digest::SHA2.hexdigest(raw_cache_key) }
    let(:last_modified_time) { Time.parse("2025-10-10") }
    let(:last_modified_header) { last_modified_time.httpdate }

    context "when values for header are valid" do
      subject { described_class.new({}, {}) }

      it "sets ETag header correctly" do
        subject.etag = raw_cache_key

        expect(subject.headers[Rage::Response::ETAG_HEADER]).to eq(etag)
      end

      it "sets Last-Modified header correctly" do
        subject.last_modified = last_modified_time

        expect(subject.headers[Rage::Response::LAST_MODIFIED_HEADER]).to eq(last_modified_header)
      end
    end

    context "when values for header are invalid" do
      let(:headers) do
        {
          Rage::Response::LAST_MODIFIED_HEADER => last_modified_header,
          Rage::Response::ETAG_HEADER => etag
        }
      end

      it "does not set ETag header" do
        subject.etag = nil

        expect(subject.headers[Rage::Response::ETAG_HEADER]).to eq(etag)
      end

      it "does not set Last-Modified header" do
        subject.last_modified = nil

        expect(subject.headers[Rage::Response::LAST_MODIFIED_HEADER]).to eq(last_modified_header)
      end

      it "does not throw an error" do
        subject.headers[Rage::Response::LAST_MODIFIED_HEADER] = "invalid time"

        expect { subject.last_modified }.to_not raise_error
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Response do
  let(:headers) { {} }
  let(:body) { {} }

  subject { described_class.new(headers, body) }

  describe "#etag" do
    let(:etag) { "1234" }
    let(:headers) { { Rage::Response::ETAG_HEADER => etag } }

    it "returns the etag" do
      expect(subject.etag).to eq(etag)
    end
  end

  describe "#etag=" do
    context "when passed ETag value is neither String nor nil" do
      let(:etag) { {} }
      let(:expected_error) { "Expected `String` but `#{etag.class}` is received" }

      it "raises ArgumentError" do
        expect { subject.etag = etag }.to raise_error(ArgumentError, expected_error)
      end
    end

    context "when passed ETag value is nil" do
      let(:etag) { "1234" }
      let(:headers) { { Rage::Response::ETAG_HEADER => etag } }

      it "sets ETag header to nil" do
        expect { subject.etag = nil }.
          to change { subject.headers[Rage::Response::ETAG_HEADER] }.
          from(etag).to(nil)
      end
    end

    context "when passed ETag value is String" do
      let(:expected_etag) { %(W/"#{Digest::SHA1.hexdigest("1234")}") }
      let(:etag) { "1234" }
      let(:headers) { { Rage::Response::ETAG_HEADER => etag } }

      it "sets ETag header to be hash of the given value" do
        expect { subject.etag = etag }.
          to change { subject.headers[Rage::Response::ETAG_HEADER] }.
          to(expected_etag)
      end
    end
  end

  describe "#last_modified" do
    context "when Last-Modified header is String" do
      let(:last_modified) { Time.utc(2025, 5, 5) }
      let(:headers) { { Rage::Response::LAST_MODIFIED_HEADER => last_modified.httpdate } }

      it "returns Last-Modified date" do
        expect(subject.last_modified).to eq(last_modified.httpdate)
      end
    end

    context "when Last-Modified header is nil" do
      let(:headers) { { Rage::Response::LAST_MODIFIED_HEADER => nil } }

      it "returns nil" do
        expect(subject.last_modified).to be_nil
      end
    end
  end

  context "#last_modified=" do
    context "when passed Last-Modified value neither Time nor nil" do
      let(:last_modified) { {} }
      let(:last_modified_header) { Time.utc(2025, 5, 5) }
      let(:headers) { { Rage::Response::LAST_MODIFIED_HEADER => last_modified_header } }

      it "raises ArgumentError" do
        expect { subject.last_modified = last_modified }.to raise_error(ArgumentError, "Expected `Time` but `#{last_modified.class}` is received")
      end

      it "does not change value in headers itself" do
        expect {
          begin
            subject.last_modified = last_modified
          rescue ArgumentError
            # skip block for testing purposes
          end
        }.not_to change { subject.headers[Rage::Response::LAST_MODIFIED_HEADER] }.from(last_modified_header)
      end
    end

    context "when passed Last-Modified value is Time" do
      let(:last_modified) { Time.utc(2025, 5, 5) }

      it "sets Last-Modified header" do
        expect { subject.last_modified = last_modified }.to change { subject.headers[Rage::Response::LAST_MODIFIED_HEADER] }.to(last_modified.httpdate)
      end
    end

    context "when passed Last-Modified value is nil" do
      let(:last_modified_header) { Time.utc(2025, 5, 5).httpdate }
      let(:headers) { { Rage::Response::LAST_MODIFIED_HEADER => last_modified_header } }

      it "sets Last-Modified header to nil" do
        expect { subject.last_modified = nil }.to change { subject.headers[Rage::Response::LAST_MODIFIED_HEADER] }.
          from(last_modified_header).to(nil)
      end
    end
  end
end

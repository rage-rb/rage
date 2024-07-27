# frozen_string_literal: true

require "stringio"

RSpec.describe Rage::ParamsParser do
  subject { described_class.prepare(env, url_params) }

  let(:query_params) { {} }
  let(:json_params) { {} }
  let(:urlencoded_params) { {} }
  let(:multipart_params) { {} }
  let(:url_params) { {} }

  let(:body) { :test_body if json_params.any? || urlencoded_params.any? || multipart_params.any? }
  let(:query_string) { query_params.any? ? :test_query_string_from_env : "" }
  let(:content_type) do
    if json_params.any?
      "application/json"
    elsif urlencoded_params.any?
      "application/x-www-form-urlencoded"
    else
      "multipart/form-data; boundary=--aa123"
    end
  end
  let(:rack_input) { instance_double(StringIO, read: body) }

  let(:env) do
    {
      "IODINE_HAS_BODY" => !!body,
      "QUERY_STRING" => query_string,
      "CONTENT_TYPE" => content_type,
      "rack.input" => rack_input
    }
  end

  before do
    if query_params.any?
      allow(Iodine::Rack::Utils).to receive(:parse_nested_query).with(query_string).and_return(query_params)
    end

    if json_params.any?
      allow(JSON).to receive(:parse).with(body, symbolize_names: true).and_return(json_params)
    elsif urlencoded_params.any?
      allow(Iodine::Rack::Utils).to receive(:parse_urlencoded_nested_query).with(body).and_return(urlencoded_params)
    elsif multipart_params.any?
      allow(Iodine::Rack::Utils).to receive(:parse_multipart).with(rack_input, content_type).and_return(multipart_params)
    end
  end

  it "returns url params when the request is empty" do
    expect(subject).to equal(url_params)
  end

  context "with query string" do
    let(:query_params) { { id: "15", count: "2" } }

    it "returns query string params" do
      expect(subject).to equal(query_params)
    end
  end

  context "with malformed query string" do
    let(:query_string) { "query" }

    before do
      allow(Iodine::Rack::Utils).to receive(:parse_nested_query).and_raise("test error")
    end

    it "raises an error" do
      expect { subject }.to raise_error(Rage::Errors::BadRequest)
    end
  end

  context "with url params" do
    let(:url_params) { { id: "10" } }

    it "returns url params" do
      expect(subject).to equal(url_params)
    end
  end

  context "with query string and url params" do
    let(:url_params) { { id: "10" } }
    let(:query_params) { { timestamp: "1539343257" } }

    it "returns merged params" do
      expect(subject).to eq({ id: "10", timestamp: "1539343257" })
    end

    context "with conflicting params" do
      let(:query_params) { { id: "20", timestamp: "1539343257" } }

      it "prioritizes url params" do
        expect(subject).to eq({ id: "10", timestamp: "1539343257" })
      end
    end
  end

  context "with json body" do
    let(:json_params) { { id: 5, timestamp: "1539343257", neighbor_ids: [3, 2], valid: true } }

    it "returns body params" do
      expect(subject).to equal(json_params)
    end
  end

  context "with malformed json body" do
    let(:json_params) { { test: true } }

    before do
      allow(JSON).to receive(:parse).and_raise("test error")
    end

    it "raises an error" do
      expect { subject }.to raise_error(Rage::Errors::BadRequest)
    end
  end

  context "with urlencoded body" do
    let(:urlencoded_params) { { slug: "SQjG", parent_ids: %w(4 5), valid: "" } }

    it "returns body params" do
      expect(subject).to equal(urlencoded_params)
    end
  end

  context "with malformed urlencoded body" do
    let(:urlencoded_params) { { test: true } }

    before do
      allow(Iodine::Rack::Utils).to receive(:parse_urlencoded_nested_query).and_raise("test error")
    end

    it "returns body params" do
      expect { subject }.to raise_error(Rage::Errors::BadRequest)
    end
  end

  context "with multipart body" do
    let(:multipart_params) { { test_request: "multipart" } }

    it "returns body params" do
      expect(subject).to equal(multipart_params)
    end
  end

  context "with malformed multipart body" do
    let(:multipart_params) { { test: true } }

    before do
      allow(Iodine::Rack::Utils).to receive(:parse_multipart).and_raise("test error")
    end

    it "raises an error" do
      expect { subject }.to raise_error(Rage::Errors::BadRequest)
    end
  end

  context "with unknown content type" do
    let(:body) { "test" }
    let(:content_type) { "text/plain" }

    it "defaults to multipart" do
      expect(Iodine::Rack::Utils).to receive(:parse_multipart).once
      subject
    end
  end

  context "with json body and query string" do
    let(:json_params) { { id: 20, timestamp: "1539343257" } }
    let(:query_params) { { reset_cache: "true" } }

    it "returns merged params" do
      expect(subject).to eq({ id: 20, timestamp: "1539343257", reset_cache: "true" })
    end
  end

  context "with urlencoded body and query string" do
    let(:urlencoded_params) { { id: "15", description: "test description" } }
    let(:query_params) { { reset_cache: "true" } }

    it "returns merged params" do
      expect(subject).to eq({ id: "15", description: "test description", reset_cache: "true" })
    end
  end

  context "with multipart body and query string" do
    let(:multipart_params) { { id: "13" } }
    let(:query_params) { { timestamp: "1539343257" } }

    it "returns merged params" do
      expect(subject).to eq({ id: "13", timestamp: "1539343257" })
    end
  end

  context "with json body and url params" do
    let(:json_params) { { location_id: 10 } }
    let(:url_params) { { id: "7" } }

    it "returns merged params" do
      expect(subject).to eq({ location_id: 10, id: "7" })
    end

    context "with conflicting params" do
      let(:json_params) { { id: 10 } }

      it "prioritizes url params" do
        expect(subject).to eq({ id: "7" })
      end
    end
  end

  context "with urlencoded body and url params" do
    let(:urlencoded_params) { { location_id: "15" } }
    let(:url_params) { { id: "5", parent_id: "10" } }

    it "returns merged params" do
      expect(subject).to eq({ id: "5", parent_id: "10", location_id: "15" })
    end

    context "with conflicting params" do
      let(:urlencoded_params) { { id: "20", location_id: "25" } }

      it "prioritizes url params" do
        expect(subject).to eq({ id: "5", parent_id: "10", location_id: "25" })
      end
    end
  end

  context "with multipart body and url params" do
    let(:multipart_params) { { location_id: "11", name: "test" } }
    let(:url_params) { { id: "10" } }

    it "returns merged params" do
      expect(subject).to eq({ id: "10", location_id: "11", name: "test" })
    end

    context "with conflicting params" do
      let(:multipart_params) { { id: "11", name: "test" } }

      it "prioritizes url params" do
        expect(subject).to eq({ id: "10", name: "test" })
      end
    end
  end

  context "with json body and query and url params" do
    let(:json_params) { { location_id: "10" } }
    let(:url_params) { { id: "11" } }
    let(:query_params) { { product_id: "12" } }

    it "returns merged params" do
      expect(subject).to eq({ location_id: "10", id: "11", product_id: "12" })
    end

    context "with conflicting params" do
      let(:url_params) { { location_id: "11" } }
      let(:query_params) { { location_id: "12" } }

      it "prioritizes url params" do
        expect(subject).to eq({ location_id: "11" })
      end
    end
  end

  context "with urlencoded body and query and url params" do
    let(:urlencoded_params) { { location_id: "10", timestamp: "1539343257" } }
    let(:url_params) { { id: "11" } }
    let(:query_params) { { product_id: "12" } }

    it "returns merged params" do
      expect(subject).to eq({ location_id: "10", timestamp: "1539343257", id: "11", product_id: "12" })
    end

    context "with conflicting params" do
      let(:url_params) { { location_id: "11" } }
      let(:query_params) { { location_id: "12" } }

      it "prioritizes url params" do
        expect(subject).to eq({ location_id: "11", timestamp: "1539343257" })
      end
    end
  end

  context "with multipart body and query and url params" do
    let(:multipart_params) { { id: "10" } }
    let(:url_params) { { location_id: "11" } }
    let(:query_params) { { product_id: "12" } }

    it "returns body params" do
      expect(subject).to eq({ id: "10", location_id: "11", product_id: "12" })
    end

    context "with conflicting params" do
      let(:url_params) { { id: "11" } }
      let(:query_params) { { id: "12" } }

      it "prioritizes url params" do
        expect(subject).to eq({ id: "11" })
      end
    end
  end
end

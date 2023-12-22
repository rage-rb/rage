# frozen_string_literal: true

module ControllerApiConditionalGetSpec
  TestModel = Struct.new(:updated_at)

  class TestController < RageController::API
    def stale_last_modified_test
      return unless stale?(last_modified: Time.utc(2023, 12, 1))

      render plain: "test_last_modified"
    end

    def stale_etag_test
      return unless stale?(etag: "123")

      render plain: "test_etag"
    end

    def stale_last_modified_and_etag_test
      return unless stale?(last_modified: Time.utc(2023, 12, 1), etag: "123")

      render plain: "test_last_modified_and_etag"
    end

    def no_freshness_info_in_response_test
      render plain: "test_no_freshness_info_in_response"
    end
  end
end

RSpec.describe RageController::API do
  let(:klass) { ControllerApiConditionalGetSpec::TestController }

  context "when IF-MODIFIED-SINCE is given" do
    context "but last_modified is not set in the action" do
      let(:env) { { "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s } }

      it "executes the action normally" do
        expect(run_action(klass, :no_freshness_info_in_response_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_no_freshness_info_in_response"]]
        )
      end
    end

    context "and it's more recent than the requested content" do
      let(:env) { { "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s } }

      it "returns NOT MODIFIED" do
        expect(run_action(klass, :stale_last_modified_test, env:)).to match(
          [304, an_instance_of(Hash), []]
        )
      end
    end

    context "and it's less recent that the requested content" do
      let(:env) { { "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 11, 15).to_s } }

      it "renders the requested resource" do
        expect(run_action(klass, :stale_last_modified_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_last_modified"]]
        )
      end
    end
  end

  context "when IF-MODIFIED-SINCE is not given" do
    let(:env) { {} }

    context "and last_modified is not set in the action" do
      it "executes the action normally" do
        expect(run_action(klass, :no_freshness_info_in_response_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_no_freshness_info_in_response"]]
        )
      end
    end

    context "and last_modified is set in the action" do
      it "renders the requested resource" do
        expect(run_action(klass, :stale_last_modified_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_last_modified"]]
        )
      end
    end
  end

  context "when IF-NONE-MATCH is given" do
    context "but etag is not set in the action" do
      let(:env) { { "HTTP_IF_NONE_MATCH" => "123" } }

      it "executes the action normally" do
        expect(run_action(klass, :no_freshness_info_in_response_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_no_freshness_info_in_response"]]
        )
      end
    end

    context "and a matching etag is set in the action" do
      let(:env) { { "HTTP_IF_NONE_MATCH" => "123" } }

      it "returns NOT MODIFIED" do
        expect(run_action(klass, :stale_etag_test, env:)).to match(
          [304, an_instance_of(Hash), []]
        )
      end
    end

    context "and a non-matching etag is set in the action" do
      let(:env) { { "HTTP_IF_NONE_MATCH" => "456" } }

      it "renders the requested resource" do
        expect(run_action(klass, :stale_etag_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_etag"]]
        )
      end
    end
  end

  context "when IF-NONE-MATCH contains a wildcard" do
    let(:env) { { "HTTP_IF_NONE_MATCH" => "*" } }

    it "returns NOT MODIFIED" do
      expect(run_action(klass, :stale_etag_test, env:)).to match(
        [304, an_instance_of(Hash), []]
      )
    end
  end

  context "when IF-NONE-MATCH is not given" do
    let(:env) { {} }

    context "and etag is not set in the action" do
      it "executes the action normally" do
        expect(run_action(klass, :no_freshness_info_in_response_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_no_freshness_info_in_response"]]
        )
      end
    end

    context "and etag is set in the action" do
      it "renders the requested resource" do
        expect(run_action(klass, :stale_etag_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_etag"]]
        )
      end
    end
  end

  context "when both IF-MODIFIED-SINCE and IF-NONE-MATCH are given" do
    context "and request is fresh" do
      let(:env) do
        {
          "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s,
          "HTTP_IF_NONE_MATCH" => "123"
        }
      end

      it "returns NOT MODIFIED" do
        expect(run_action(klass, :stale_last_modified_and_etag_test, env:)).to match(
          [304, an_instance_of(Hash), []]
        )
      end
    end

    context "and request is stale" do
      let(:env) do
        {
          "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 11, 15).to_s,
          "HTTP_IF_NONE_MATCH" => "123"
        }
      end

      it "renders the requested resource" do
        expect(run_action(klass, :stale_last_modified_and_etag_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_last_modified_and_etag"]]
        )
      end
    end

    context "and request is fresh but etag does not match" do
      let(:env) do
        {
          "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s,
          "HTTP_IF_NONE_MATCH" => "456"
        }
      end

      it "renders the requested resource" do
        expect(run_action(klass, :stale_last_modified_and_etag_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_last_modified_and_etag"]]
        )
      end
    end

    context "and etag is not set in the action" do
      let(:env) do
        {
          "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s,
          "HTTP_IF_NONE_MATCH" => "123"
        }
      end

      it "renders the requested resource" do
        expect(run_action(klass, :stale_last_modified_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_last_modified"]]
        )
      end
    end

    context "and last_modified is not set in the action" do
      let(:env) do
        {
          "HTTP_IF_MODIFIED_SINCE" => Time.utc(2023, 12, 15).to_s,
          "HTTP_IF_NONE_MATCH" => "123"
        }
      end

      it "renders the requested resource" do
        expect(run_action(klass, :stale_etag_test, env:)).to match(
          [200, an_instance_of(Hash), ["test_etag"]]
        )
      end
    end
  end
end

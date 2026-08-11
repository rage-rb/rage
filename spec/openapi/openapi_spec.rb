# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI do
  describe ".application" do
    subject(:app) { described_class.application }

    let(:first_env) do
      {
        "PATH_INFO" => "/",
        "SCRIPT_NAME" => "/docs-a",
        "HTTP_HOST" => "first.test:3000",
        "rack.url_scheme" => "http"
      }
    end

    let(:second_env) do
      {
        "PATH_INFO" => "/",
        "SCRIPT_NAME" => "/docs-b",
        "HTTP_HOST" => "second.test:4000",
        "rack.url_scheme" => "https"
      }
    end

    before do
      allow(Rage.config).to receive(:middleware).and_return([])
    end

    it "renders a request-independent html page" do
      _, _, first_body = app.call(first_env)
      _, _, second_body = app.call(second_env)

      expect(first_body.join).to eq(second_body.join)
      expect(first_body.join).to include('url: window.location.pathname.replace(/\/?$/, "/json"),')
      expect(first_body.join).not_to include("first.test:3000")
      expect(first_body.join).not_to include("/docs-a/json")
    end
  end

  describe ".__try_parse_collection" do
    subject { described_class.__try_parse_collection(input) }

    context "with Array" do
      context "with a class" do
        let(:input) { "Array<UserResource>" }
        it { is_expected.to eq([true, "UserResource"]) }
      end

      context "with a namespaced class" do
        let(:input) { "Array<Api::V1::UserResource>" }
        it { is_expected.to eq([true, "Api::V1::UserResource"]) }
      end

      context "with a namespaced class with namespace resolution" do
        let(:input) { "Array<::Api::V1::UserResource>" }
        it { is_expected.to eq([true, "::Api::V1::UserResource"]) }
      end

      context "with a class with config" do
        let(:input) { "Array<UserResource(view: :extended)>" }
        it { is_expected.to eq([true, "UserResource(view: :extended)"]) }
      end
    end

    context "with []" do
      context "with a class" do
        let(:input) { "[UserResource]" }
        it { is_expected.to eq([true, "UserResource"]) }
      end

      context "with a namespaced class" do
        let(:input) { "[Api::V1::UserResource]" }
        it { is_expected.to eq([true, "Api::V1::UserResource"]) }
      end

      context "with a namespaced class with namespace resolution" do
        let(:input) { "[::Api::V1::UserResource]" }
        it { is_expected.to eq([true, "::Api::V1::UserResource"]) }
      end

      context "with a class with config" do
        let(:input) { "[UserResource(view: :extended)]" }
        it { is_expected.to eq([true, "UserResource(view: :extended)"]) }
      end
    end

    context "without collection" do
      context "with a class" do
        let(:input) { "UserResource" }
        it { is_expected.to eq([false, "UserResource"]) }
      end

      context "with a namespaced class" do
        let(:input) { "Api::V1::UserResource" }
        it { is_expected.to eq([false, "Api::V1::UserResource"]) }
      end

      context "with a namespaced class with namespace resolution" do
        let(:input) { "::Api::V1::UserResource" }
        it { is_expected.to eq([false, "::Api::V1::UserResource"]) }
      end

      context "with a class with config" do
        let(:input) { "UserResource(view: :extended)" }
        it { is_expected.to eq([false, "UserResource(view: :extended)"]) }
      end
    end
  end

  describe ".__parse_serializer_options" do
    subject { described_class.__parse_serializer_args(str) }

    context "with a plain class name" do
      let(:str) { "UserBlueprint" }
      it { is_expected.to eq([false, "UserBlueprint", {}]) }
    end

    context "with a view option" do
      let(:str) { "UserBlueprint(view: :extended)" }
      it { is_expected.to eq([false, "UserBlueprint", { view: :extended }]) }
    end

    context "with multiple options" do
      let(:str) { "UserBlueprint(view: :extended, root: :user)" }
      it { is_expected.to eq([false, "UserBlueprint", { view: :extended, root: :user }]) }
    end

    context "with a collection using square brackets without options" do
      let(:str) { "[UserBlueprint]" }
      it { is_expected.to eq([true, "UserBlueprint", {}]) }
    end

    context "with a collection using Array syntax without options" do
      let(:str) { "Array<UserBlueprint>" }
      it { is_expected.to eq([true, "UserBlueprint", {}]) }
    end

    context "with a collection using square brackets with options" do
      let(:str) { "[UserBlueprint(view: :extended)]" }
      it { is_expected.to eq([true, "UserBlueprint", { view: :extended }]) }
    end

    context "with a collection using Array syntax with options" do
      let(:str) { "Array<UserBlueprint(view: :extended)>" }
      it { is_expected.to eq([true, "UserBlueprint", { view: :extended }]) }
    end

    context "with unknown options" do
      let(:str) { "UserBlueprint(unknown_option: :something)" }

      it "does not raise" do
        expect { subject }.not_to raise_error
      end

      it { is_expected.to eq([false, "UserBlueprint", { unknown_option: :something }]) }
    end

    context "with existing Alba syntax unchanged" do
      let(:str) { "UserResource" }
      it { is_expected.to eq([false, "UserResource", {}]) }
    end

    context "with a collection using Array syntax with multiple options" do
      let(:str) { "Array<UserBlueprint(view: :extended, root: :user)>" }
      it { is_expected.to eq([true, "UserBlueprint", { view: :extended, root: :user }]) }
    end

    context "with a plain string value without quotes" do
      let(:str) { "UserBlueprint(root: users)" }
      it { is_expected.to eq([false, "UserBlueprint", { root: "users" }]) }
    end
  end

  describe ".__parse_keywords" do
    subject { described_class.__parse_keywords(str) }

    context "with nil" do
      let(:str) { nil }
      it { is_expected.to eq({}) }
    end

    context "with empty string" do
      let(:str) { "" }
      it { is_expected.to eq({}) }
    end

    context "with a symbol value" do
      let(:str) { "view: :extended" }
      it { is_expected.to eq({ view: :extended }) }
    end

    context "with a string value" do
      let(:str) { 'name: "hello"' }
      it { is_expected.to eq({ name: "hello" }) }
    end

    context "with a boolean true value" do
      let(:str) { "active: true" }
      it { is_expected.to eq({ active: true }) }
    end

    context "with a boolean false value" do
      let(:str) { "admin: false" }
      it { is_expected.to eq({ admin: false }) }
    end

    context "with a nil value" do
      let(:str) { "key:" }
      it { is_expected.to eq({ key: nil }) }
    end

    context "with multiple options" do
      let(:str) { "view: :extended, root: :user" }
      it { is_expected.to eq({ view: :extended, root: :user }) }
    end

    context "with an invalid option (not a key value pair)" do
      let(:str) { "extended" }
      it { is_expected.to be_nil }
    end
  end

  describe ".__module_parent" do
    subject { described_class.__module_parent(klass) }

    context "with one module" do
      let(:klass) { double(name: "Api::UsersController") }

      it do
        expect(Object).to receive(:const_get).with("Api")
        subject
      end
    end

    context "with multiple modules" do
      let(:klass) { double(name: "Api::Internal::V1::UsersController") }

      it do
        expect(Object).to receive(:const_get).with("Api::Internal::V1")
        subject
      end
    end

    context "with no modules" do
      let(:klass) { double(name: "UsersController") }
      it { is_expected.to eq(Object) }
    end
  end

  describe ".__log_warn" do
    it "prints a warning" do
      expect { described_class.__log_warn("something went wrong") }.
        to output("[OpenAPI] WARNING: something went wrong\n").to_stdout
    end

    it "does not retain the warning when not collecting" do
      allow(described_class).to receive(:puts)

      described_class.__log_warn("something went wrong")

      expect(described_class.instance_variable_get(:@__warnings)).to be_nil
    end
  end

  describe ".__collect_warnings" do
    before do
      allow(described_class).to receive(:puts)
    end

    it "returns the warnings logged inside the block" do
      warnings = described_class.__collect_warnings do
        described_class.__log_warn("first")
        described_class.__log_warn("second")
      end

      expect(warnings).to eq(["first", "second"])
    end

    it "returns an empty array when nothing was logged" do
      expect(described_class.__collect_warnings {}).to eq([])
    end

    it "stops collecting once the block returns" do
      described_class.__collect_warnings { described_class.__log_warn("first") }
      described_class.__log_warn("second")

      expect(described_class.__collect_warnings {}).to eq([])
    end

    it "stops collecting if the block raises" do
      expect {
        described_class.__collect_warnings { raise "boom" }
      }.to raise_error("boom")

      expect(described_class.instance_variable_get(:@__warnings)).to be_nil
    end
  end

  describe ".__type_to_spec" do
    subject { described_class.__type_to_spec(type) }

    context "with Float" do
      let(:type) { "Float" }
      it { is_expected.to eq({ "type" => "number", "format" => "float" }) }
    end

    context "with Boolean" do
      let(:type) { "Boolean" }
      it { is_expected.to eq({ "type" => "boolean" }) }
    end

    context "with String" do
      let(:type) { "String" }
      it { is_expected.to eq({ "type" => "string" }) }
    end

    context "with File" do
      let(:type) { "File" }
      it { is_expected.to eq({ "type" => "string", "format" => "binary" }) }
    end

    context "with unknown type" do
      context "with fallback" do
        subject { described_class.__type_to_spec(type, default: true) }
        let(:type) { "Symbol" }

        it do
          expect(subject).to eq({ "type" => "string" })
        end
      end

      context "without fallback" do
        let(:type) { "Symbol" }

        it do
          expect(subject).to be_nil
        end
      end
    end
  end
end

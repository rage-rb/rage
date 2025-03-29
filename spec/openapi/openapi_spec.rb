# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI do
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

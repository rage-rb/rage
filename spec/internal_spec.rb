# frozen_string_literal: true

RSpec.describe Rage::Internal do
  describe ".build_arguments" do
    subject { described_class.build_arguments(method, arguments) }

    context "with no parameters" do
      let(:method) { proc {} }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("")
      end
    end

    context "with a subset of parameters" do
      let(:method) { proc { |arg2:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with extra parameters" do
      let(:method) { proc { |arg2:, arg3:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with default parameters" do
      let(:method) { proc { |arg2: 123| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with all parameters" do
      let(:method) { proc { |arg1:, arg2:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg1: true, arg2: false")
      end
    end

    context "with splat" do
      let(:method) { proc { |arg1:, **| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg1: true, arg2: false")
      end
    end
  end
end

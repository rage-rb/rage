# frozen_string_literal: true

RSpec.describe Rage::Env do
  subject { described_class.new(env) }

  context "with standard env" do
    let(:env) { "development" }

    it "correctly responds to `development?`" do
      expect(subject).to be_development
    end

    it "correctly responds to `==`" do
      expect(subject).to eq("development")
    end

    it "correctly responds to `to_s`" do
      expect(subject.to_s).to eq("development")
    end

    it "correctly responds to `to_str`" do
      expect(subject.to_str).to eq("development")
    end

    it "correctly responds to `to_sym`" do
      expect(subject.to_sym).to eq(:development)
    end

    it "correctly responds to `production?`" do
      expect(subject).not_to be_production
    end

    it "correctly responds to non-standard methods" do
      expect(subject).not_to be_staging2
    end

    it "correctly defines methods" do
      expect(subject).to respond_to(:development?)
      expect(subject).to respond_to(:production?)
      expect(subject).to respond_to(:staging2?)
    end

    it "raises on missing methods" do
      expect { subject.development }.to raise_error(NoMethodError)
    end
  end

  context "with non-standard env" do
    let(:env) { "staging2" }

    it "correctly responds to `development?`" do
      expect(subject).not_to be_development
    end

    it "correctly responds to `==`" do
      expect(subject).to eq("staging2")
    end

    it "correctly responds to `to_s`" do
      expect(subject.to_s).to eq("staging2")
    end

    it "correctly responds to `to_sym`" do
      expect(subject.to_sym).to eq(:staging2)
    end

    it "correctly responds to `staging2?`" do
      expect(subject).to be_staging2
    end
  end
end

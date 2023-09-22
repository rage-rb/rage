# frozen_string_literal: true

module ControllerApiSkipBeforeActionsInheritanceSpec
  class TestController < RageController::API
    def index
      render plain: "index"
    end
  end

  class TestController2 < TestController
    before_action :setup

    private def setup
      verifier.setup
    end
  end

  class TestController3 < TestController2
    skip_before_action :setup, only: :index

    def show
      render plain: "show"
    end
  end

  class TestController4 < TestController3
    skip_before_action :setup
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiSkipBeforeActionsInheritanceSpec::TestController }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiSkipBeforeActionsInheritanceSpec::TestController2 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiSkipBeforeActionsInheritanceSpec::TestController3 }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiSkipBeforeActionsInheritanceSpec::TestController4 }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end
  end
end

# frozen_string_literal: true

module ControllerApiSkipBeforeActionsSpec
  class TestController < RageController::API
    before_action :setup
    skip_before_action :setup, only: :show

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController2 < RageController::API
    before_action :setup, only: %i(index show)
    skip_before_action :setup, only: :show

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController3 < RageController::API
    before_action :setup, only: %i(index show)
    skip_before_action :setup, except: :index

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController4 < RageController::API
    before_action :setup, except: %i(destroy)
    skip_before_action :setup, only: :index

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    def destroy
      render plain: "destroy"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController5 < RageController::API
    before_action :setup
    skip_before_action :setup, only: :index

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    def destroy
      render plain: "destroy"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController6 < RageController::API
    before_action :setup, except: :destroy
    skip_before_action :setup

    def index
      render plain: "index"
    end

    def show
      render plain: "show"
    end

    def destroy
      render plain: "destroy"
    end

    private def setup
      verifier.setup
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController2 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController3 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController4 }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :destroy)).to match([200, instance_of(Hash), ["destroy"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController5 }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :destroy)).to match([200, instance_of(Hash), ["destroy"]])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiSkipBeforeActionsSpec::TestController6 }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["show"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :destroy)).to match([200, instance_of(Hash), ["destroy"]])
    end
  end

  context "case 7" do
    let(:klass) do
      Class.new(RageController::API) do
        skip_before_action :setup
      end
    end

    it "raises an error" do
      expect { klass }.to raise_error(/couldn't be found/)
    end
  end
end

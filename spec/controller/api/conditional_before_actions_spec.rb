# frozen_string_literal: true

module ControllerApiConditionalBeforeActionsSpec
  class TestController < RageController::API
    before_action :setup, if: -> { params[:setup] }

    def index
      render plain: "hi"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController2 < RageController::API
    before_action :setup, unless: :setup?

    def index
      render plain: "hi"
    end

    private

    def setup?
      !!params[:setup]
    end

    def setup
      verifier.setup
    end
  end

  class TestController3 < RageController::API
    before_action :setup, if: -> { params[:setup] }, unless: -> { params[:no_setup] }

    def index
      render plain: "hi"
    end

    private

    def setup
      verifier.setup
    end
  end

  class TestController4 < RageController::API
    before_action :setup, only: :index, if: -> { false }

    def index
      render plain: "hi"
    end

    private

    def setup
      verifier.setup
    end
  end

  class TestController5 < RageController::API
    before_action :setup, except: :index, if: -> { true }

    def index
      render plain: "hi"
    end

    private

    def setup
      verifier.setup
    end
  end

  class TestController6Base < RageController::API
    before_action :setup_1, if: -> { false }

    def index
      render plain: "hi"
    end

    private

    def setup_1
      verifier.setup_1
    end
  end

  class TestController6 < TestController6Base
    before_action :setup_2, if: -> { true }

    def index
      render plain: "hi"
    end

    private

    def setup_2
      verifier.setup_2
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }
  let(:params) { {} }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
    # TODO: remove this once we support real params
    allow_any_instance_of(RageController::API).to receive(:params).and_return(params)
  end

  context "case 1" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController }

    it "correctly runs before actions" do
      params[:setup] = true
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "doesn't run before actions" do
      params[:setup] = false
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController2 }

    it "correctly runs before actions" do
      params[:setup] = false
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "doesn't run before actions" do
      params[:setup] = true
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController3 }

    it "correctly runs before actions" do
      params[:setup] = true
      params[:no_setup] = false
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "correctly runs before actions" do
      params[:setup] = false
      params[:no_setup] = false
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "correctly runs before actions" do
      params[:setup] = true
      params[:no_setup] = true
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "correctly runs before actions" do
      params[:setup] = false
      params[:no_setup] = true
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController4 }

    it "favoures `only` over `if`" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController5 }

    it "favoures `if` over `except`" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiConditionalBeforeActionsSpec::TestController6 }

    it "doesn't override inherited methods" do
      expect(verifier).not_to receive(:setup_1)
      expect(verifier).to receive(:setup_2).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end
end

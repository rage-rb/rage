# frozen_string_literal: true

module ControllerApiBeforeActionsSpec
  class TestController < RageController::API
    before_action :setup

    def index
      render plain: "hi"
    end

    private def setup
      verifier.setup
    end
  end

  class TestController2 < RageController::API
    before_action :continue_action, only: :index
    before_action :stop_action, except: %i[index]

    def index
      render plain: "hi from index"
    end

    def show
      render plain: "hi from show"
    end

    private

    def continue_action
      verifier.continue_action
    end

    def stop_action
      verifier.stop_action
      head :forbidden
    end
  end

  class TestController3 < RageController::API
    before_action :setup_1
    before_action :setup_2
    before_action :setup_3, only: :show

    def index
      render plain: "hi from index"
    end

    def show
      render plain: "hi from show"
    end

    private

    def setup_1
      verifier.setup_1
    end

    def setup_2
      verifier.setup_2
    end

    def setup_3
      verifier.setup_3
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController2 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:continue_action).once
      expect(verifier).not_to receive(:stop_action)

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:continue_action)
      expect(verifier).to receive(:stop_action).once

      expect(run_action(klass, :show)).to match([403, instance_of(Hash), []])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController3 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup_1).once
      expect(verifier).to receive(:setup_2).once
      expect(verifier).not_to receive(:setup_3)

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup_1).once
      expect(verifier).to receive(:setup_2).once
      expect(verifier).to receive(:setup_3).once

      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["hi from show"]])
    end
  end
end

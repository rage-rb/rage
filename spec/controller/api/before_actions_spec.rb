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

  class TestController4 < TestController
    before_action :setup_4

    def index
      render plain: "hi from index"
    end

    private def setup_4
      verifier.setup_4
    end
  end

  class TestController5 < TestController
    before_action :setup, only: :show

    def index
      render plain: "hi from index"
    end

    def show
      render plain: "hi from show"
    end
  end

  class TestController6Base < RageController::API
    def index
      render plain: "hi from base"
    end
  end

  class TestController6 < TestController6Base
    before_action :setup_6

    def index
      render plain: "hi from child"
    end

    private def setup_6
      verifier.setup_6
    end
  end

  class TestController7 < RageController::API
    before_action do
      setup_1
      setup_2
    end

    def index
      render plain: "hi from index"
    end

    private

    def setup_1
      verifier.setup_1
    end

    def setup_2
      verifier.setup_2
    end
  end

  class TestController8 < TestController7
    before_action do
      setup_3
    end

    def index
      render plain: "hi from index"
    end

    private

    def setup_3
      verifier.setup_3
    end
  end

  class TestController9 < RageController::API
    before_action :stop_action
    before_action :continue_action

    def index
      render plain: "hi from index"
    end

    private

    def stop_action
      verifier.stop_action
      head :forbidden
    end

    def continue_action
      verifier.continue_action
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

  context "case 4" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController4 }
    let(:base_klass) { ControllerApiBeforeActionsSpec::TestController }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(verifier).to receive(:setup_4).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(verifier).not_to receive(:setup_4)
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController5 }
    let(:base_klass) { ControllerApiBeforeActionsSpec::TestController }

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["hi from show"]])
    end

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup).once
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController6 }
    let(:base_klass) { ControllerApiBeforeActionsSpec::TestController6Base }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup_6).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from child"]])
    end

    it "correctly runs before actions" do
      expect(verifier).not_to receive(:setup_6)
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi from base"]])
    end
  end

  context "case 7" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController7 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup_1).once
      expect(verifier).to receive(:setup_2).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end
  end

  it "raises an error if the action name is missing and a block is not pass" do
    expect do
      Class.new(RageController::API) {
        before_action only: [:index]
      }
    end.to raise_error("No handler provided. Pass the `action_name` parameter or provide a block.")
  end

  context "case 8" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController8 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:setup_1).once
      expect(verifier).to receive(:setup_2).once
      expect(verifier).to receive(:setup_3).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end
  end

  context "case 9" do
    let(:klass) { ControllerApiBeforeActionsSpec::TestController9 }

    it "correctly runs before actions" do
      expect(verifier).to receive(:stop_action).once
      expect(run_action(klass, :index)).to match([403, instance_of(Hash), []])
    end
  end
end

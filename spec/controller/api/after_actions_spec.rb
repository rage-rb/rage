# frozen_string_literal: true

module ControllerApiAfterActionsSpec
  class TestController < RageController::API
    after_action :after

    def index
      render plain: "hi"
    end

    private def after
      verifier.after
    end
  end

  class TestController2 < RageController::API
    after_action :action_1, only: :index
    after_action :action_2, except: %i[index]

    def index
      render plain: "hi from index"
    end

    def show
      render plain: "hi from show"
    end

    private

    def action_1
      verifier.action_1
    end

    def action_2
      verifier.action_2
    end
  end

  class TestController3 < RageController::API
    after_action :action_1
    after_action :action_2
    after_action :action_3, only: :show

    def index
      render plain: "hi from index"
    end

    def show
      render plain: "hi from show"
    end

    private

    def action_1
      verifier.action_1
    end

    def action_2
      verifier.action_2
    end

    def action_3
      verifier.action_3
    end
  end

  class TestController4 < TestController
    after_action :after_4

    def index
      render plain: "hi from index"
    end

    private def after_4
      verifier.after_4
    end
  end

  class TestController5 < TestController
    after_action :after, only: :show

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
    after_action :after_6

    def index
      render plain: "hi from child"
    end

    private def after_6
      verifier.after_6
    end
  end

  class TestController7 < RageController::API
    after_action do
      action_1
      action_2
    end

    def index
      render plain: "hi from index"
    end

    private

    def action_1
      verifier.action_1
    end

    def action_2
      verifier.action_2
    end
  end

  class TestController8 < TestController7
    after_action do
      action_3
    end

    def index
      render plain: "hi from index"
    end

    private

    def action_3
      verifier.action_3
    end
  end

  class TestController9 < RageController::API
    after_action do
      render plain: "i should raise"
    end

    def index
    end
  end

  class TestController10 < RageController::API
    after_action do
      verifier.after
    end

    def index
      raise "test error"
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController }

    it "correctly runs after actions" do
      expect(verifier).to receive(:after).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController2 }

    it "correctly runs after actions" do
      expect(verifier).to receive(:action_1).once
      expect(verifier).not_to receive(:action_2)

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs after actions" do
      expect(verifier).not_to receive(:action_1)
      expect(verifier).to receive(:action_2).once

      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["hi from show"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController3 }

    it "correctly runs after actions" do
      expect(verifier).to receive(:action_1).once
      expect(verifier).to receive(:action_2).once
      expect(verifier).not_to receive(:action_3)

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs after actions" do
      expect(verifier).to receive(:action_1).once
      expect(verifier).to receive(:action_2).once
      expect(verifier).to receive(:action_3).once

      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["hi from show"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController4 }
    let(:base_klass) { ControllerApiAfterActionsSpec::TestController }

    it "correctly runs after actions" do
      expect(verifier).to receive(:after).once
      expect(verifier).to receive(:after_4).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs after actions" do
      expect(verifier).to receive(:after).once
      expect(verifier).not_to receive(:after_4)
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController5 }
    let(:base_klass) { ControllerApiAfterActionsSpec::TestController }

    it "correctly runs after actions" do
      expect(verifier).not_to receive(:after)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end

    it "correctly runs after actions" do
      expect(verifier).to receive(:after).once
      expect(run_action(klass, :show)).to match([200, instance_of(Hash), ["hi from show"]])
    end

    it "correctly runs after actions" do
      expect(verifier).to receive(:after).once
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController6 }
    let(:base_klass) { ControllerApiAfterActionsSpec::TestController6Base }

    it "correctly runs after actions" do
      expect(verifier).to receive(:after_6).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from child"]])
    end

    it "correctly runs after actions" do
      expect(verifier).not_to receive(:after_6)
      expect(run_action(base_klass, :index)).to match([200, instance_of(Hash), ["hi from base"]])
    end
  end

  context "case 7" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController7 }

    it "correctly runs after actions" do
      expect(verifier).to receive(:action_1).once
      expect(verifier).to receive(:action_2).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end
  end

  context "case 8" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController8 }

    it "correctly runs after actions" do
      expect(verifier).to receive(:action_1).once
      expect(verifier).to receive(:action_2).once
      expect(verifier).to receive(:action_3).once
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from index"]])
    end
  end

  context "case 9" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController9 }

    it "correctly runs after actions" do
      expect { run_action(klass, :index) }.to raise_error("Render was called multiple times in this action")
    end
  end

  context "case 10" do
    let(:klass) { ControllerApiAfterActionsSpec::TestController10 }

    it "correctly runs after actions" do
      expect(verifier).not_to receive(:after)
      expect { run_action(klass, :index) }.to raise_error("test error")
    end
  end

  context "with invalid arguments" do
    it "raises an error if action name is missing and a block is not passed" do
      expect {
        Class.new(RageController::API) {
          after_action only: :index
        }
      }.to raise_error(/No handler provided/)
    end

    it "raises an error if no arguments are passed" do
      expect {
        Class.new(RageController::API) {
          after_action only: :index
        }
      }.to raise_error(/No handler provided/)
    end
  end
end

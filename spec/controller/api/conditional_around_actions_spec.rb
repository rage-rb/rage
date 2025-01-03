# frozen_string_literal: true

module ControllerApiConditionalAroundActionsSpec
  class TestController < RageController::API
    around_action :with_transaction, if: -> { params[:setup] }

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.around_action
      yield
    end
  end

  class TestController2 < RageController::API
    around_action :with_transaction, unless: -> { params[:setup] }

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.around_action
      yield
    end
  end

  class TestController3 < RageController::API
    around_action :with_transaction, if: -> { params[:setup] }

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.around_action
    end
  end

  class TestController4 < RageController::API
    around_action :with_transaction, if: -> { params[:setup] }

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      render plain: "hi from around_action"
    end
  end

  class TestController5 < RageController::API
    around_action :with_transaction
    around_action :with_duration, if: -> { params[:with_duration] }
    around_action :with_log

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
    end

    def with_duration
      verifier.with_duration
    end

    def with_log
      verifier.with_log
    end
  end

  class TestController6 < RageController::API
    around_action :with_transaction, if: -> { params[:with_transaction] }
    around_action :with_duration
    around_action :with_log

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
    end

    def with_duration
      verifier.with_duration
    end

    def with_log
      verifier.with_log
    end
  end

  class TestController7 < RageController::API
    around_action :with_transaction
    around_action :with_duration, if: -> { params[:with_duration] }
    around_action :with_log, if: -> { params[:with_log] }

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
      yield
    end

    def with_duration
      verifier.with_duration
      yield
    end

    def with_log
      verifier.with_log
    end
  end

  class TestController8 < RageController::API
    around_action :with_transaction, if: -> { params[:with_transaction] }
    around_action :with_duration, if: -> { params[:with_duration] }

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
    end

    def with_duration
      yield
      verifier.with_duration
    end
  end

  class TestController9 < RageController::API
    around_action :with_transaction, if: -> { params[:with_transaction] }
    around_action :with_duration, if: -> { params[:with_duration] }

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
    end

    def with_duration
      verifier.with_duration
    end
  end

  class TestController10 < RageController::API
    around_action :with_transaction, if: -> { params[:with_transaction] }
    before_action :verify_access
    around_action :with_duration, if: -> { params[:with_duration] }

    def index
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.with_transaction
      yield
    end

    def verify_access
      verifier.verify_access
      head :forbidden
    end

    def with_duration
      verifier.with_duration
      yield
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }
  let(:params) { {} }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController }

    it "correctly runs around actions" do
      params[:setup] = true
      expect(verifier).to receive(:around_action)
      expect(verifier).to receive(:action)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "doesn't run around actions" do
      params[:setup] = false
      expect(verifier).to receive(:action)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController2 }

    it "correctly runs around actions" do
      params[:setup] = true
      expect(verifier).to receive(:action)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end

    it "doesn't run around actions" do
      params[:setup] = false
      expect(verifier).to receive(:around_action)
      expect(verifier).to receive(:action)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController3 }

    it "correctly runs around actions" do
      params[:setup] = true
      expect(verifier).to receive(:around_action)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:setup] = false
      expect(verifier).to receive(:action)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController4 }

    it "correctly runs around actions" do
      params[:setup] = true
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi from around_action"]])
    end

    it "doesn't run around actions" do
      params[:setup] = false
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController5 }

    it "correctly runs around actions" do
      params[:with_duration] = true
      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:with_duration] = false
      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController6 }

    it "correctly runs around actions" do
      params[:with_transaction] = true
      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:with_transaction] = false
      expect(verifier).to receive(:with_duration)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 7" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController7 }

    it "correctly runs around actions" do
      params[:with_duration] = true
      params[:with_log] = true

      expect(verifier).to receive(:with_transaction).ordered
      expect(verifier).to receive(:with_duration).ordered
      expect(verifier).to receive(:with_log).ordered
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:with_duration] = true
      params[:with_log] = false

      expect(verifier).to receive(:with_transaction).ordered
      expect(verifier).to receive(:with_duration).ordered
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 8" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController8 }

    it "correctly runs around actions" do
      params[:with_transaction] = true
      params[:with_duration] = true

      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:with_transaction] = true
      params[:with_duration] = false

      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "skips one action" do
      params[:with_transaction] = false
      params[:with_duration] = true

      expect(verifier).to receive(:with_duration)
      expect(run_action(klass, :index, params:)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 9" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController9 }

    it "correctly runs around actions" do
      params[:with_transaction] = true
      params[:with_duration] = true

      expect(verifier).to receive(:with_transaction)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end

    it "doesn't run around actions" do
      params[:with_transaction] = false
      params[:with_duration] = true

      expect(verifier).to receive(:with_duration)
      expect(run_action(klass, :index, params:)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 10" do
    let(:klass) { ControllerApiConditionalAroundActionsSpec::TestController10 }

    it "correctly runs around actions" do
      params[:with_transaction] = true
      params[:with_duration] = true

      expect(verifier).to receive(:with_transaction).ordered
      expect(verifier).to receive(:verify_access).ordered

      expect(run_action(klass, :index, params:)).to match([403, instance_of(Hash), []])
    end

    it "skips around actions" do
      params[:with_transaction] = true
      params[:with_duration] = false

      expect(verifier).to receive(:with_transaction).ordered
      expect(verifier).to receive(:verify_access).ordered

      expect(run_action(klass, :index, params:)).to match([403, instance_of(Hash), []])
    end
  end
end

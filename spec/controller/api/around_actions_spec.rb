# frozen_string_literal: true

module ControllerApiAroundActionsSpec
  class TestController < RageController::API
    around_action :with_transaction

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end
  end

  class TestController2 < RageController::API
    around_action :with_transaction
    around_action :with_duration

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end
  end

  class TestController3 < RageController::API
    around_action :with_transaction
    before_action :setup
    around_action :with_duration

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def setup
      verifier.setup_before_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end
  end

  class TestController4 < RageController::API
    after_action :add_headers

    around_action :with_transaction
    before_action :setup

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def add_headers
      verifier.headers_after_action
    end

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def setup
      verifier.setup_before_action
    end
  end

  class TestController5 < RageController::API
    around_action :with_transaction

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_action
    end
  end

  class TestController6 < RageController::API
    around_action :with_transaction

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_action
      render plain: "hi from transaction"
    end
  end

  class TestController7 < RageController::API
    around_action :with_transaction
    around_action :with_duration

    before_action do
      verifier.before_action
      render plain: "hi from before_action"
    end

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end
  end

  class TestController8 < RageController::API
    before_action do
      verifier.before_action
      render plain: "hi from before_action"
    end

    around_action :with_transaction
    around_action :with_duration

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end
  end

  class TestController9 < RageController::API
    around_action :with_transaction

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      render plain: "hi from around_action"
      yield
      verifier.transaction_after_action
    end
  end

  class TestController10 < RageController::API
    around_action :with_transaction
    after_action :add_headers

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.around_action
    end

    def add_headers
      verifier.after_action
    end
  end

  class TestController11 < RageController::API
    around_action :with_transaction
    around_action :with_duration
    around_action :with_logger

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end

    def with_logger
      verifier.logger_action
    end
  end

  class TestController12 < RageController::API
    around_action :with_transaction
    around_action :with_duration
    around_action :with_logger

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_before_action
      yield
      verifier.transaction_after_action
    end

    def with_duration
      verifier.duration_action
    end

    def with_logger
      verifier.before_logger_action
      yield
      verifier.after_logger_action
    end
  end

  class TestController13 < RageController::API
    around_action :with_transaction
    around_action :with_duration
    around_action :with_logger

    def index
      verifier.action
      render plain: "hi"
    end

    private

    def with_transaction
      verifier.transaction_action
    end

    def with_duration
      verifier.duration_before_action
      yield
      verifier.duration_after_action
    end

    def with_logger
      verifier.before_logger_action
      yield
      verifier.after_logger_action
    end
  end
end

RSpec.describe RageController::API do
  let(:verifier) { double }

  before do
    allow_any_instance_of(RageController::API).to receive(:verifier).and_return(verifier)
  end

  context "case 1" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 2" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController2 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:duration_before_action).ordered
      expect(verifier).to receive(:action).ordered
      expect(verifier).to receive(:duration_after_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 3" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController3 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:setup_before_action).ordered
      expect(verifier).to receive(:duration_before_action).ordered
      expect(verifier).to receive(:action).ordered
      expect(verifier).to receive(:duration_after_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 4" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController4 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:setup_before_action).ordered
      expect(verifier).to receive(:action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered
      expect(verifier).to receive(:headers_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi"]])
    end
  end

  context "case 5" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController5 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_action)
      expect(run_action(klass, :index)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 6" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController6 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_action)
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from transaction"]])
    end
  end

  context "case 7" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController7 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:duration_before_action).ordered
      expect(verifier).to receive(:before_action).ordered
      expect(verifier).to receive(:duration_after_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from before_action"]])
    end
  end

  context "case 8" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController8 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:before_action).ordered
      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from before_action"]])
    end
  end

  context "case 9" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController9 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([200, instance_of(Hash), ["hi from around_action"]])
    end
  end

  context "case 10" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController10 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:around_action).ordered
      expect(verifier).to receive(:after_action).ordered

      expect(run_action(klass, :index)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 11" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController11 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:duration_before_action).ordered
      expect(verifier).to receive(:logger_action).ordered
      expect(verifier).to receive(:duration_after_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 12" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController12 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_before_action).ordered
      expect(verifier).to receive(:duration_action).ordered
      expect(verifier).to receive(:transaction_after_action).ordered

      expect(run_action(klass, :index)).to match([204, instance_of(Hash), []])
    end
  end

  context "case 13" do
    let(:klass) { ControllerApiAroundActionsSpec::TestController13 }

    it "correctly runs around actions" do
      expect(verifier).to receive(:transaction_action).ordered
      expect(run_action(klass, :index)).to match([204, instance_of(Hash), []])
    end
  end
end

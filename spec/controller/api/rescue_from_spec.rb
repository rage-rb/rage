# frozen_string_literal: true

module RescueFromSpec
  class TestController1 < RageController::API
    rescue_from StandardError, with: :error_handler

    def index
      raise "111"
      render plain: "hi"
    end

    private def error_handler(e)
      render plain: "error #{e.message}", status: 500
    end
  end

  class TestController2 < RageController::API
    rescue_from StandardError, with: :standard_error_handler
    rescue_from NoMethodError, with: :no_method_error_handler

    def index
      [].Print
    end

    private def standard_error_handler(_)
      render plain: "standard error"
    end

    private def no_method_error_handler(_)
      render plain: "no method error"
    end
  end

  class TestController3 < RageController::API
    rescue_from NoMethodError, NameError, ArgumentError, with: :error_handler

    def index
      who_am_i
    end

    private def error_handler(e)
      render plain: "error #{e.class}"
    end
  end

  class TestController4 < TestController1
    def index
      raise "222"
    end
  end

  class TestController5Base < RageController::API
    rescue_from ArgumentError, with: :base_error_handler

    def index
      raise RangeError
    end

    private def base_error_handler(_)
      render plain: "base error handler"
    end
  end

  class TestController5 < TestController5Base
    rescue_from RangeError, with: :child_error_handler

    private def child_error_handler(_)
      render plain: "child error handler"
    end
  end

  class TestController6 < RageController::API
    rescue_from StandardError do |_|
      render plain: "block error handler", status: 500
    end

    def index
      raise "123"
    end
  end

  class TestController7 < RageController::API
    rescue_from StandardError, with: :error_handler

    def index
      raise "111"
      render plain: "hi"
    end

    private def error_handler
      render plain: "error", status: 500
    end
  end

  class TestController8 < RageController::API
    rescue_from StandardError do
      render plain: "block error", status: 500
    end

    def index
      raise "111"
      render plain: "hi"
    end
  end
end

RSpec.describe RageController::API do
  subject { run_action(klass, :index) }

  context "case 1" do
    let(:klass) { RescueFromSpec::TestController1 }

    it "correctly handles exceptions" do
      expect(subject).to match([500, instance_of(Hash), ["error 111"]])
    end
  end

  context "case 2" do
    let(:klass) { RescueFromSpec::TestController2 }

    it "correctly handles exceptions" do
      expect(subject).to match([200, instance_of(Hash), ["no method error"]])
    end
  end

  context "case 3" do
    let(:klass) { RescueFromSpec::TestController3 }

    it "correctly handles exceptions" do
      expect(subject).to match([200, instance_of(Hash), ["error NameError"]])
    end
  end

  context "case 4" do
    let(:klass) { RescueFromSpec::TestController4 }

    it "correctly handles exceptions" do
      expect(subject).to match([500, instance_of(Hash), ["error 222"]])
    end
  end

  context "case 5" do
    let(:klass) { RescueFromSpec::TestController5Base }

    it "raises an exception" do
      expect { subject }.to raise_error(RangeError)
    end

    context "with a correct error handler" do
      let(:klass) { RescueFromSpec::TestController5 }

      it "correctly handles exceptions" do
        expect(subject).to match([200, instance_of(Hash), ["child error handler"]])
      end
    end
  end

  context "case 6" do
    let(:klass) { RescueFromSpec::TestController6 }

    it "correctly handles exceptions" do
      expect(subject).to match([500, instance_of(Hash), ["block error handler"]])
    end
  end

  context "case 7" do
    let(:klass) { RescueFromSpec::TestController7 }

    it "correctly handles exceptions" do
      expect(subject).to match([500, instance_of(Hash), ["error"]])
    end
  end

  context "case 8" do
    let(:klass) { RescueFromSpec::TestController8 }

    it "correctly handles exceptions" do
      expect(subject).to match([500, instance_of(Hash), ["block error"]])
    end
  end
end

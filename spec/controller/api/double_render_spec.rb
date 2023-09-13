# frozen_string_literal: true

module ControllerApiDoubleRenderSpec
  class TestController < RageController::API
    def show
      render json: { message: "hello world" }
      render status: :created
    end
  end
end

RSpec.describe RageController::API do
  let(:klass) { ControllerApiDoubleRenderSpec::TestController }

  it "raises and error" do
    expect { run_action(klass, :show) }.to raise_error(/Render was called multiple times in this action/)
  end
end

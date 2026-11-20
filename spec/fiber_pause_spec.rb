# frozen_string_literal: true

RSpec.describe "Fiber.pause" do
  let(:deferred) { [] }

  before do
    allow(Iodine).to receive(:defer) { |&block| deferred << block }
  end

  it "resumes the fiber in the next iteration" do
    resumed = false
    fiber = Fiber.new do
      Fiber.pause
      resumed = true
    end

    fiber.resume
    deferred.each(&:call)

    expect(resumed).to be(true)
  end

  it "doesn't resume a fiber that was killed while paused" do
    fiber = Fiber.new { Fiber.pause }

    fiber.resume
    fiber.kill

    expect { deferred.each(&:call) }.not_to raise_error
  end
end

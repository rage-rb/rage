# frozen_string_literal: true

require "net/http"

RSpec.describe Rage::FiberScheduler do
  TEST_HTTP_URL = ENV.fetch("TEST_HTTP_URL")
  TEST_PG_URL = ENV.fetch("TEST_PG_URL")

  before :all do
    Fiber.set_scheduler(described_class.new)
  end

  it "correctly performs long http GET" do
    within_reactor do
      num = rand
      result = Net::HTTP.get(URI("#{TEST_HTTP_URL}/long-http-get?i=#{num}"))
      -> { expect(result.to_f).to eq(num * 10) }
    end
  end
end

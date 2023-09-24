# frozen_string_literal: true

require "net/http"
require "benchmark"

RSpec.describe Fiber do
  before :all do
    Fiber.set_scheduler(Rage::FiberScheduler.new)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  it "correctly watches on fibers" do
    within_reactor do
      result = Fiber.await(
        Fiber.schedule { 10 },
        Fiber.schedule { 20 },
      )

      -> { expect(result).to eq([10, 20]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await(
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[1]}")) },
      )

      -> { expect(result).to eq([(num[0] * 10).to_s, (num[1] * 10).to_s]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await(
        Fiber.schedule { 111 },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[1]}")) },
        Fiber.schedule { 222 },
      )

      -> { expect(result).to eq([111, (num[0] * 10).to_s, (num[1] * 10).to_s, 222]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await(
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{num[1]}")) },
      )

      -> { expect(result).to eq([(num[0] * 10).to_s, (num[1] * 10).to_s]) }
    end
  end

  it "processes fibers in parallel" do
    within_reactor do
      result = Benchmark.realtime do
        Fiber.await(
          Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{rand}")) },
          Fiber.schedule { sleep(1) },
          Fiber.schedule { sleep(1) },
        )
      end

      -> { expect(result).to be < 1.5 }
    end
  end

  it "correctly watches on one fiber" do
    within_reactor do
      num = rand

      result = Fiber.await(
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{num}")) },
      )

      -> { expect(result).to eq([(num * 10).to_s]) }
    end
  end

  it "correctly watches on an empty list" do
    expect(Fiber.await).to eq([])
  end

  it "correctly watches on terminated fibers" do
    within_reactor do
      fiber = Fiber.schedule { 125 }

      -> do
        expect(Fiber.await(fiber)).to eq([125])
        expect(Fiber.await(fiber)).to eq([125])
      end
    end
  end
end

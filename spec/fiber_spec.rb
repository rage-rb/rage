# frozen_string_literal: true

require "net/http"
require "benchmark"

RSpec.describe Fiber do
  before :all do
    skip("skipping fiber tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    Fiber.set_scheduler(Rage::FiberScheduler.new)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  it "correctly watches on fibers" do
    within_reactor do
      result = Fiber.await([
        Fiber.schedule { 10 },
        Fiber.schedule { 20 }
      ])

      -> { expect(result).to eq([10, 20]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await([
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[1]}")) }
      ])

      -> { expect(result).to eq([(num[0] * 10).to_s, (num[1] * 10).to_s]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await([
        Fiber.schedule { 111 },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[1]}")) },
        Fiber.schedule { 222 }
      ])

      -> { expect(result).to eq([111, (num[0] * 10).to_s, (num[1] * 10).to_s, 222]) }
    end
  end

  it "correctly watches on fibers" do
    within_reactor do
      num = [rand, rand]

      result = Fiber.await([
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{num[0]}")) },
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{num[1]}")) }
      ])

      -> { expect(result).to eq([(num[0] * 10).to_s, (num[1] * 10).to_s]) }
    end
  end

  it "processes fibers in parallel" do
    within_reactor do
      result = Benchmark.realtime do
        Fiber.await([
          Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{rand}")) },
          Fiber.schedule { sleep(1) },
          Fiber.schedule { sleep(1) }
        ])
      end

      -> { expect(result).to be < 1.5 }
    end
  end

  it "processes fibers in parallel" do
    within_reactor do
      result = Benchmark.realtime do
        Fiber.await([
          Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{rand}")) },
          Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{rand}")) }
        ])
      end

      -> { expect(result).to be < 1.5 }
    end
  end

  it "correctly watches on one fiber" do
    within_reactor do
      num = rand

      result = Fiber.await([
        Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{num}")) }
      ])

      -> { expect(result).to eq([(num * 10).to_s]) }
    end
  end

  it "correctly watches on an empty list" do
    expect(Fiber.await([])).to eq([])
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

  it "swallows exceptions from inner fibers without Fiber.await" do
    within_reactor do
      Fiber.schedule { raise "can't see me" }
      -> {}
    end
  end

  it "propagates exceptions from inner fibers to Fiber.await" do
    within_reactor do
      Fiber.await([
        Fiber.schedule { sleep(0.2) },
        Fiber.schedule { sleep(0.2) && raise("inner raise") }
      ])

      raise "failed!"

    rescue => e
      -> { expect(e.message).to eq("inner raise") }
    end
  end

  it "doesn't wait for all fibers if one errored out" do
    within_reactor do
      results = []

      Fiber.await([
        Fiber.schedule { sleep(1); results << 1 },
        Fiber.schedule { sleep(1); results << 2 },
        Fiber.schedule { sleep(0.2); raise }
      ])

    rescue
      -> { expect(results).to be_empty }
    end
  end

  it "doesn't wait for all fibers if one errored out" do
    within_reactor do
      results = []

      Fiber.await([
        Fiber.schedule { sleep(1); results << 1 },
        Fiber.schedule { raise }
      ])

    rescue
      -> { expect(results).to be_empty }
    end
  end

  it "returns errors right away" do
    within_reactor do
      Fiber.await([
        Fiber.schedule { 111 },
        Fiber.schedule { raise }
      ])

    rescue => e
      -> { expect(e).to be_a(StandardError) }
    end
  end

  it "correctly processes several awaits in a row" do
    within_reactor do
      Fiber.await(Fiber.schedule { sleep 0.1 })
      Fiber.await(Fiber.schedule { sleep 0.2 })
      Fiber.await(Fiber.schedule { sleep 0.3 })

      -> {}
    end
  end
end

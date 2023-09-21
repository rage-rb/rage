# frozen_string_literal: true

require "net/http"
require "digest"

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

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/700b.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("174d893e34d9e551466f9e6808358cebc7fd91c5cf9a07300a18e035abc0c4a9") }
    end
  end

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/2kb.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("73ad9fa79f6266fad72c925e5ba197ba296aa433ae5d0f792e87c19e79df798a") }
    end
  end

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/10kb.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("ec6f95fa1b9b256aeed3d21c0b982822e642079dabd5a032929a993b614815d8") }
    end
  end

  it "correctly writes files" do
    within_reactor do
      str = 100.times.map { rand(1..100) }.join
      File.write("test", str)

      -> { expect(File.read("test")).to eq(str) }
    end

    File.unlink("test")
  end

  it "correctly writes files" do
    within_reactor do
      str = 500_000.times.map { rand(1..100) }.join
      File.write("test", str)

      -> { expect(File.read("test")).to eq(str) }
    end

    File.unlink("test")
  end
end

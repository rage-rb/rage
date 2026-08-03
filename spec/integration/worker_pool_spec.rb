# frozen_string_literal: true

require "http"
require "benchmark"

RSpec.describe "Worker pool" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: { "RAGE_ENV" => "production" })
  end

  after :all do
    stop_server
  end

  it "offloads nogvl tasks to a worker pool" do
    3.times do
      Thread.new { HTTP.get("http://localhost:3000/busy") }
    end

    sleep 0.1

    time_spent = Benchmark.realtime do
      HTTP.get("http://localhost:3000/async/short_sleep")
    end

    expect(time_spent).to be < 0.1
  end
end

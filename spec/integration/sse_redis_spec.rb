# frozen_string_literal: true

require "http"

RSpec.describe "SSE" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server(env: { "ENABLE_REDIS_ADAPTER" => "1" })
  end

  after :all do
    stop_server
  end

  it "broadcasts messages using the adapter" do
    thread = Thread.new { HTTP.timeout(5).persistent("http://localhost:3000").get("/sse/subscribe") }

    script = <<~RUBY
      require_relative("config/application")

      Rage::SSE.broadcast("test-stream", { message: "message from another process" })
      Rage::SSE.close_stream("test-stream")
    RUBY

    Bundler.with_unbundled_env do
      system({ "ENABLE_REDIS_ADAPTER" => "1" }, "ruby -e '#{script}'", chdir: "spec/integration/test_app")
    end

    response = thread.value.to_s
    expect(response).to start_with("data: ")

    data = response.delete_prefix("data: ").strip
    expect(JSON.parse(data)).to eq({ "message" => "message from another process" })
  end
end

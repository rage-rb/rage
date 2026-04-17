# frozen_string_literal: true

require "http"

RSpec.describe "SSE" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server
  end

  after :all do
    stop_server
  end

  describe "headers" do
    it "returns correct content-type" do
      response = HTTP.headers(accept: "text/event-stream").get("http://localhost:3000/sse/object")
      expect(response.headers["content-type"]).to eq("text/event-stream; charset=utf-8")
    end

    it "returns 200 status" do
      response = HTTP.headers(accept: "text/event-stream").get("http://localhost:3000/sse/object")
      expect(response.code).to eq(200)
    end

    context "with non-SSE content type" do
      it "returns 200 status" do
        response = HTTP.headers(accept: "application/json").get("http://localhost:3000/sse/object")
        expect(response.code).to eq(200)
      end
    end
  end

  describe "object mode" do
    it "correctly serializes objects" do
      response = HTTP.persistent("http://localhost:3000").get("/sse/object")

      data = response.to_s
      expect(data.delete_prefix!("data: ")).not_to be_nil
      expect(data.chomp!("\n\n")).not_to be_nil

      expect(JSON.parse(data)).to eq({ "status" => "ok", "count" => 42 })
    end
  end

  describe "stream mode" do
    it "correctly streams responses" do
      response = HTTP.persistent("http://localhost:3000").get("/sse/stream")

      chunks = response.to_s.split("\n\n")
      expect(chunks.size).to eq(3)

      expect(chunks[0]).to eq("data: first")
      expect(chunks[1]).to eq("data: second\nid: 2\nevent: update")
      expect(JSON.parse(chunks[2].delete_prefix("data: "))).to eq({ "data" => "third" })
    end

    it "doesn't buffer responses" do
      response = HTTP.persistent("http://localhost:3000").get("/sse/stream")

      chunks_arrive_timestamps = response.body.filter_map do |chunk|
        Time.now.to_f unless chunk.empty?
      end

      expect(chunks_arrive_timestamps.size).to eq(3)

      chunks_arrive_timestamps.each_cons(2) do |timestamp_a, timestamp_b|
        expect(timestamp_b - timestamp_a).to be > 0.08
      end
    end
  end

  describe "raw mode" do
    it "correctly streams responses" do
      response = HTTP.persistent("http://localhost:3000").get("/sse/proc")

      chunks = response.to_s.split("\n\n")
      expect(chunks.size).to eq(2)

      expect(chunks[0]).to eq("data: hello")
      expect(chunks[1]).to eq("data: world")
    end
  end

  describe "POST request" do
    it "correctly processes request" do
      response = HTTP.persistent("http://localhost:3000").post("/sse/object")

      expect(response.code).to eq(200)
      expect(response.to_s).to match(/"count":42/)
    end
  end

  describe "broadcast mode" do
    it "correctly broadcasts responses" do
      response = HTTP.timeout(2).persistent("http://localhost:3000").get("/sse/broadcast")

      chunks = response.to_s.split("\n\n")
      expect(chunks.size).to eq(5)
      expect(chunks.uniq).to eq(["data: test message"])
    end
  end
end

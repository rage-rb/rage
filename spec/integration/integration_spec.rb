# frozen_string_literal: true

require "http"
require "benchmark"

RSpec.describe "End-to-end" do
  before :all do
    skip("skipping end-to-end tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    launch_server
  end

  after :all do
    stop_server
  end

  it "correctly processes lambda requests" do
    response = HTTP.get("http://localhost:3000")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("It works!")
  end

  it "correctly processes get requests" do
    response = HTTP.get("http://localhost:3000/get")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("i am a get response")
  end

  it "correctly processes post requests" do
    response = HTTP.post("http://localhost:3000/post")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("i am a post response")
  end

  it "correctly processes put requests" do
    response = HTTP.put("http://localhost:3000/put")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("i am a put response")
  end

  it "correctly processes patch requests" do
    response = HTTP.patch("http://localhost:3000/patch")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("i am a patch response")
  end

  it "correctly processes delete requests" do
    response = HTTP.delete("http://localhost:3000/delete")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("i am a delete response")
  end

  it "correctly processes empty requests" do
    response = HTTP.get("http://localhost:3000/empty")
    expect(response.code).to eq(204)
    expect(response.to_s).to eq("")
  end

  it "correctly responds with 404" do
    response = HTTP.get("http://localhost:3000/unknown")
    expect(response.code).to eq(404)
  end

  it "correctly responds with 500" do
    response = HTTP.get("http://localhost:3000/raise_error")
    expect(response.code).to eq(500)
    expect(response.to_s).to start_with("RuntimeError (1155 test error)")
  end

  it "correctly fetches current action name" do
    response = HTTP.get("http://localhost:3000/get_action_name")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("get_action_name_action")
  end

  it "correctly fetches route URI pattern" do
    response = HTTP.get("http://localhost:3000/get_route_uri_pattern/123")
    expect(response.code).to eq(200)
    expect(response.to_s).to eq("/get_route_uri_pattern/:id")
  end

  it "sets correct headers" do
    response = HTTP.get("http://localhost:3000/get")
    expect(response.headers["content-type"]).to eq("text/plain; charset=utf-8")
  end

  it "correctly uses middlewares" do
    response = HTTP.headers("Test-Middleware" => "true").get("http://localhost:3000/get")
    expect(response.code).to eq(206)
    expect(response.to_s).to eq("response from middleware")
  end

  context "with params" do
    it "correctly parses query params" do
      response = HTTP.get("http://localhost:3000/params/digest?test=true&message=hello+world")
      expect(response.code).to eq(200)
      expect(response.to_s).to eq("e51b2c9c5399485acbc88f60f4f782c5")
    end

    it "correctly parses url params" do
      response = HTTP.get("http://localhost:3000/params/1144/defaults")
      expect(response.code).to eq(200)
      expect(response.to_s).to eq("49d0c01df27b9b15b558554439bdfd00")
    end

    it "correctly parses json body" do
      response = HTTP.post("http://localhost:3000/params/digest?hello=w+o+r+l+d", json: { id: 10, test: true })
      expect(response.code).to eq(200)
      expect(response.to_s).to eq("beda497e73ccdbe91c140377b9dc5e48")
    end

    it "correctly parses multipart body" do
      response = HTTP.post("http://localhost:3000/params/multipart", form: {
        id: 12345,
        text: HTTP::FormData::File.new("spec/fixtures/2kb.txt")
      })

      expect(response.code).to eq(200)
      expect(response.to_s).to eq("662b82a8999aa1ce53d67dcc6d3e3605")
    end

    it "correctly parses urlencoded body" do
      response = HTTP.post("http://localhost:3000/params/digest", form: {
        "users[][id]" => 11,
        "users[][name]" => 22
      })

      expect(response.code).to eq(200)
      expect(response.to_s).to eq("0f825fc37d17c300570e3252ea648563")
    end
  end

  context "with async" do
    it "correctly pauses and resumes requests" do
      response = HTTP.get("http://localhost:3000/async/sum")
      expect(response.code).to eq(200)
      expect(response.to_s).to eq("192")
    end

    it "doesn't block" do
      threads = nil

      time_spent = Benchmark.realtime do
        threads = 3.times.map do |i|
          Thread.new { HTTP.get("http://localhost:3000/async/long?i=#{10 + i}") }
        end
        threads.each(&:join)
      end

      responses = threads.map(&:value)
      expect(responses.map(&:code).uniq).to eq([200])
      expect(responses.map(&:to_s)).to match_array(%w(100 110 120))

      expect(time_spent).to be < 1.5
    end

    it "correctly sends default response" do
      response = HTTP.timeout(2).get("http://localhost:3000/async/empty")
      expect(response.code).to eq(204)
      expect(response.to_s).to eq("")
    end

    it "correctly processes exceptions from inner fibers" do
      response = HTTP.get("http://localhost:3000/async/raise_error")
      expect(response.code).to eq(500)
      expect(response.to_s).to include("raised from inner fiber")
    end

    it "corrrectly processes short sleep calls" do
      response = HTTP.get("http://localhost:3000/async/short_sleep")
      expect(response.code).to eq(200)
    end
  end

  context "with before actions" do
    it "correctly processes the request" do
      response = HTTP.get("http://localhost:3000/before_actions/get")
      expect(response.parse).to eq({ "message" => "hello world" })
    end

    it "correctly processes the request" do
      response = HTTP.get("http://localhost:3000/before_actions/get?with_timestamp=true")
      expect(response.parse).to eq({ "message" => "hello world", "timestamp" => 1636466868 })
    end
  end

  context "with logs" do
    let(:logs) { File.readlines("spec/integration/test_app/log/development.log") }

    it "correctly adds 2xx entries" do
      HTTP.get("http://localhost:3000/empty")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/empty controller=ApplicationController action=empty status=204 duration=\d+\.\d+$/)
    end

    it "correctly adds 404 entries" do
      HTTP.get("http://localhost:3000/unknown")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/unknown status=404 duration=\d+\.\d+$/)
    end

    it "correctly adds 500 entries" do
      HTTP.get("http://localhost:3000/raise_error")

      request_tag = logs.last.match(/^\[(\w{16})\]/)[1]
      request_logs = logs.select { |log| log.include?(request_tag) }

      expect(request_logs.size).to eq(2)
      expect(request_logs[0]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=error message=RuntimeError \(1155 test error\):$/)
      expect(request_logs[1]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/raise_error controller=ApplicationController action=raise_error status=500 duration=\d+\.\d+$/)
    end

    it "correctly adds non-get entries" do
      HTTP.patch("http://localhost:3000/patch")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=PATCH path=\/patch controller=ApplicationController action=patch status=200 duration=\d+\.\d+$/)
    end

    it "correctly adds custom entries" do
      HTTP.get("http://localhost:3000/logs/custom")

      request_logs = logs.last(4)
      request_tag = logs.last.match(/^\[(\w{16})\]/)[1]

      expect(request_logs[0]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info message=log_1$/)
      expect(request_logs[1]).to match(/^\[#{request_tag}\]\[tag_2\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=warn message=log_2$/)
      expect(request_logs[2]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=error test=true message=log_3$/)
      expect(request_logs[3]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/logs\/custom controller=LogsController action=custom status=204 duration=\d+\.\d+$/)
    end

    it "correctly adds entries from inner fibers" do
      HTTP.get("http://localhost:3000/logs/fiber")

      request_logs = logs.last(4)
      request_tag = logs.last.match(/^\[(\w{16})\]/)[1]

      expect(request_logs[0]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info message=outside_1$/)
      expect(request_logs[1]).to match(/^\[#{request_tag}\]\[in_fiber\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info message=inside$/)
      expect(request_logs[2]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info message=outside_2$/)
      expect(request_logs[3]).to match(/^\[#{request_tag}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/logs\/fiber controller=LogsController action=fiber status=204 duration=\d+\.\d+$/)
    end

    it "correctly adds entries from lambda handlers" do
      HTTP.get("http://localhost:3000")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/ status=200 duration=\d+\.\d+$/)
    end

    it "correctly adds root entries from mounted apps" do
      HTTP.get("http://localhost:3000/admin")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/admin status=200 duration=\d+\.\d+$/)
    end

    it "correctly adds non-root entries from mounted apps" do
      HTTP.delete("http://localhost:3000/admin/undo")
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=DELETE path=\/admin\/undo status=200 duration=\d+\.\d+$/)
    end

    it "correctly appends info" do
      HTTP.get("http://localhost:3000/logs/custom", params: { append_info_to_payload: true })
      expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info method=GET path=\/logs\/custom controller=LogsController action=custom hello=world status=204 duration=\d+\.\d+$/)
    end

    it "correctly adds cable entries" do
      with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
        expect(client).to be_connected
        expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info message=client subscribed$/)
      end
    end

    it "correctly adds cable entries with custom context" do
      with_websocket_connection("ws://localhost:3000/cable/logs?user_id=1", headers: { Origin: "localhost:3000" }) do |client|
        expect(client).to be_connected
        client.send({ message: "test-message" }.to_json)
        expect(logs.last).to match(/^\[\w{16}\] timestamp=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2} pid=\d+ level=info content=test-message message=message received$/)
      end
    end
  end

  context "with API docs" do
    it "correctly renders the OpenAPI specification" do
      response = HTTP.get("http://localhost:3000/publicapi/json")
      spec = response.parse

      expect(spec["info"]).to match({ "version" => "2.0.0", "title" => "My Test API" })
      expect(spec["components"]).to match({ "securitySchemes" => { "authenticate_user" => { "type" => "http", "scheme" => "bearer" }, "ApiKeyAuth" => { "type" => "apiKey", "in" => "header", "name" => "X-API-Key" } }, "schemas" => { "V3_User" => { "type" => "object", "properties" => { "uuid" => { "type" => "string" }, "is_admin" => { "type" => "boolean" } } } }, "responses" => { "404NotFound" => { "description" => "The specified resource was not found.", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "code" => { "type" => "string" }, "message" => { "type" => "string" } } } } } } } })
      expect(spec["tags"]).to include({ "name" => "v1/Users" }, { "name" => "v2/Users" }, { "name" => "v3/Users" })

      expect(spec["paths"]["/api/v1/users"]).to match({ "get" => { "summary" => "Returns the list of all users.", "description" => "Test description for the method.", "deprecated" => false, "security" => [{ "authenticate_user" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "email" => { "type" => "string" }, "id" => { "type" => "string" }, "name" => { "type" => "string" }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" }, "updated_at" => { "type" => "string" } } }, "address" => { "type" => "object", "properties" => { "city" => { "type" => "string" }, "zip" => { "type" => "string" }, "country" => { "type" => "string" } } } } } } } } } } } } }, "post" => { "summary" => "Creates a user.", "description" => "", "deprecated" => false, "security" => [{ "authenticate_user" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "email" => { "type" => "string" }, "id" => { "type" => "string" }, "name" => { "type" => "string" }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" }, "updated_at" => { "type" => "string" } } }, "address" => { "type" => "object", "properties" => { "city" => { "type" => "string" }, "zip" => { "type" => "string" }, "country" => { "type" => "string" } } } } } } } } } } }, "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "name" => { "type" => "string" }, "email" => { "type" => "string" }, "password" => { "type" => "string" } } } } } } } } } })
      expect(spec["paths"]["/api/v1/users/{id}"]).to match({ "parameters" => [{ "description" => "", "in" => "path", "name" => "id", "required" => true, "schema" => { "type" => "integer" } }], "get" => { "summary" => "Returns a specific user.", "description" => "", "deprecated" => false, "security" => [{ "authenticate_user" => [] }], "tags" => ["v1/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "full_name" => { "type" => "string" }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "content" => { "type" => "string" }, "created_at" => { "type" => "string" } } } } } } } } }, "404" => { "description" => "" } } } })
      expect(spec["paths"]["/api/v2/users"]).to match({ "get" => { "summary" => "Returns the list of all users.", "description" => "Test description.", "deprecated" => false, "security" => [], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "type" => "object", "properties" => { "full_name" => { "type" => "string" }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "content" => { "type" => "string" }, "created_at" => { "type" => "string" } } } } } } } } } } } } })
      expect(spec["paths"]["/api/v2/users/{id}"]).to match({ "parameters" => [{ "description" => "", "in" => "path", "name" => "id", "required" => true, "schema" => { "type" => "integer" } }], "get" => { "summary" => "Returns a specific user.", "description" => "", "deprecated" => true, "security" => [{ "authenticate_user" => [] }], "tags" => ["v2/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "full_name" => { "type" => "string" }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "content" => { "type" => "string" }, "created_at" => { "type" => "string" } } } } } } } } } } } })
      expect(spec["paths"]["/api/v3/users/{id}"]).to match({ "parameters" => [{ "description" => "", "in" => "path", "name" => "id", "required" => true, "schema" => { "type" => "integer" } }], "get" => { "summary" => "Returns a specific user.", "description" => "", "deprecated" => false, "security" => [{ "authenticate_user" => [] }], "tags" => ["v3/Users"], "responses" => { "200" => { "description" => "", "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/V3_User" } } } }, "404" => { "$ref" => "#/components/responses/404NotFound" } } } })
      expect(spec["paths"]["/api/v3/session"]["get"]["security"]).to eq([{ "ApiKeyAuth" => [] }])
    end

    it "correctly renders the html page" do
      response = HTTP.get("http://localhost:3000/publicapi")
      expect(response.code).to eq(200)
    end

    it "correctly renders the html page if the path is /" do
      response = HTTP.get("http://localhost:3000/publicapi/")
      expect(response.code).to eq(200)
    end
  end

  context "with reload" do
    let(:controller) { Pathname.new("#{__dir__}/test_app/app/controllers/reload_controller.rb") }

    before do
      @initial = controller.read
    end

    after do
      controller.write(@initial)
    end

    context "with new status" do
      before do
        controller.write <<~RUBY
          class ReloadController < RageController::API
            def verify
              head 207
            end
          end
        RUBY
      end

      it "reloads the app" do
        response = HTTP.get("http://localhost:3000/reload/verify")
        expect(response.code).to eq(207)
      end
    end

    context "with async code" do
      before do
        controller.write <<~RUBY
          class ReloadController < RageController::API
            def verify
              f1 = Fiber.schedule { sleep 0.1 }
              f2 = Fiber.schedule { sleep 0.2 }
              Fiber.await([f1, f2])

              head 205
            end
          end
        RUBY
      end

      it "reloads the app" do
        response = HTTP.get("http://localhost:3000/reload/verify")
        expect(response.code).to eq(205)
      end
    end

    context "with parallel requests" do
      before do
        controller.write <<~RUBY
          class ReloadController < RageController::API
            def verify
              sleep 0.1
              head 208
            end
          end
        RUBY
      end

      it "reloads the app" do
        requests = [
          Thread.new { HTTP.get("http://localhost:3000/reload/verify") },
          Thread.new { HTTP.get("http://localhost:3000/reload/verify") }
        ]

        requests.each(&:join)
        responses = requests.map(&:value)

        expect(responses.map(&:code).uniq).to eq([208])
      end
    end
  end

  context "with deferred tasks" do
    it "correctly processes deferred tasks" do
      file = Tempfile.create
      response = nil

      time_spent = Benchmark.realtime do
        response = HTTP.post("http://localhost:3000/deferred/create_file", json: { file_path: file.path })
      end

      expect(response.code).to eq(200)
      expect(time_spent).to be < 0.1

      expect(file.read).to be_empty
      sleep 1
      expect(file.read).to eq("EnqueueMiddleware1->EnqueueMiddleware2->PerformMiddleware1->PerformMiddleware2")
    end
  end
end

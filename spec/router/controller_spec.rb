# frozen_string_literal: true

class BaseTestController < RageController::API
end

class TestController < BaseTestController
  def index
    "test_controller"
  end
end

class TestPhotoTagsController < BaseTestController
  def index
    "test_photo_tags_controller"
  end
end

module Api
  module V1
    class TestPhotosController < BaseTestController
      def get_all
        "api/test_photos_controller"
      end
    end
  end
end

RSpec.describe Rage::Router::Backend do
  it "correctly processes a string handler" do
    expect(TestController).to receive(:__register_action).with(:index).and_return(:index)
    router.on("GET", "/test", "test#index")

    result, _ = perform_get_request("/test")
    expect(result).to eq("test_controller")
  end

  it "correctly processes a string handler" do
    expect(TestPhotoTagsController).to receive(:__register_action).with(:index).and_return(:index)
    router.on("GET", "/test", "test_photo_tags#index")

    result, _ = perform_get_request("/test")
    expect(result).to eq("test_photo_tags_controller")
  end

  it "correctly processes a string handler" do
    expect(Api::V1::TestPhotosController).to receive(:__register_action).with(:get_all).and_return(:get_all)
    router.on("GET", "/test", "api/v1/test_photos#get_all")

    result, _ = perform_get_request("/test")
    expect(result).to eq("api/test_photos_controller")
  end

  it "uses the registered action" do
    expect(TestController).to receive(:__register_action).with(:index).and_return(:registered_index)
    router.on("GET", "/test", "test#index")

    expect { perform_get_request("/test") }.to raise_error(NoMethodError, /undefined method .registered_index./)
  end

  it "raises an error in case the controller doesn't exist" do
    expect {
      router.on("GET", "/test", "unknown#index")
    }.to raise_error("Routing error: could not find the UnknownController class")
  end

  it "raises an error in case an action doesn't exist" do
    expect(TestController).to receive(:__register_action).with(:unknown).and_call_original

    expect {
      router.on("GET", "/test", "test#unknown")
    }.to raise_error(/The action `unknown` could not be found in the `TestController` controller/)
  end

  it "verifies string handler format" do
    expect {
      router.on("GET", "/test", "test")
    }.to raise_error("Invalid route handler format, expected to match the 'controller#action' pattern")
  end

  it "verifies lambda handler format" do
    expect {
      router.on("GET", "/test", Object)
    }.to raise_error("Non-string route handler should respond to `call`")
  end
end

RSpec.describe Rage::Request do
  describe "Request" do
    describe "#headers" do
      it "returns request headers with both meta-variable and original names" do
        env = {
          "CONTENT_TYPE" => "application/json",
          "HTTP_SOME_OTHER_HEADER" => "value",
          "HTTP_ACCEPT_LANGUAGE" => "en-US",
          "HTTP_VARY" => "Accept-Language"
        }
        request = Rage::Request.new(env)

        expect(request.headers["Content-Type"]).to eq("application/json")
        expect(request.headers["CONTENT_TYPE"]).to eq("application/json")
        expect(request.headers["Accept-Language"]).to eq("en-US")
        expect(request.headers["HTTP_ACCEPT_LANGUAGE"]).to eq("en-US")
        expect(request.headers["non-existent-header"]).to be_nil
        expect(request.headers["vary"]).to eq("Accept-Language")
        expect(request.headers["VARY"]).to eq("Accept-Language")
        expect(request.headers["Vary"]).to eq("Accept-Language")
      end
    end
  end
end

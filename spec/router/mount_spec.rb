RSpec.describe Rage::Router::Backend do
  it "correctly mounts a Rack app" do
    router.mount("/rack_app", ->(_) { :rack_app_response }, %w(GET HEAD))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_head_request("/rack_app")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_head_request("/rack_app/index")
    expect(result).to eq(:rack_app_response)

    result, _ = perform_post_request("/rack_app")
    expect(result).to be_nil
  end

  it "updates script name" do
    router.mount("/rack_app", ->(env) { env["SCRIPT_NAME"] }, %w(GET))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq("/rack_app")

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq("/rack_app")
  end

  it "updates path info" do
    router.mount("/rack_app", ->(env) { env["PATH_INFO"] }, %w(GET))

    result, _ = perform_get_request("/rack_app")
    expect(result).to eq("/")

    result, _ = perform_get_request("/rack_app/index")
    expect(result).to eq("/index")

    result, _ = perform_get_request("/rack_app/get/all/")
    expect(result).to eq("/get/all")
  end

  it "validates the handler" do
    expect {
      router.mount("/rack_app", 5, %w(GET))
    }.to raise_error(/should respond to `call`/)
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Router::Backend do
  it "correctly processes a static url" do
    router.on("GET", "/photos", ->(_) { "all photos" })

    result, _ = perform_get_request("/photos")
    expect(result).to eq("all photos")
  end

  it "correctly processes a static url with multiple sections" do
    router.on("GET", "/api/v1/photos", ->(_) { "api photos" })

    result, _ = perform_get_request("/api/v1/photos")
    expect(result).to eq("api photos")

    result, _ = perform_get_request("/api/v1")
    expect(result).to be_nil

    result, _ = perform_get_request("/api/v1/photo")
    expect(result).to be_nil

    result, _ = perform_get_request("/api/v1/photo/s")
    expect(result).to be_nil
  end

  it "correctly distinguishes between different methods" do
    router.on("GET", "/photos", ->(_) { "photos" })

    result, _ = perform_post_request("/photos")
    expect(result).to be_nil
  end

  it "doesn't override routes across methods" do
    router.on("GET", "/photos", ->(_) { "get photos" })
    router.on("POST", "/photos", ->(_) { "post photos" })
    router.on("PATCH", "/photos", ->(_) { "patch photos" })

    result, _ = perform_post_request("/photos")
    expect(result).to eq("post photos")
  end

  it "performs case-sensitive search" do
    router.on("GET", "/photos", ->(_) { "all photos" })

    result, _ = perform_get_request("/Photos")
    expect(result).to be_nil
  end

  it "correctly processes urls with dots" do
    router.on("GET", "/photos.jpg/all", ->(_) { "jpg photos" })

    result, _ = perform_get_request("/photos.jpg/all")
    expect(result).to eq("jpg photos")
  end

  it "correctly processes '::' in urls" do
    router.on("GET", "/photos::get", ->(_) { "get photos" })
    router.on("GET", "/api/photos::get/all", ->(_) { "get all photos" })

    result, _ = perform_get_request("/photos:get")
    expect(result).to eq("get photos")

    result, _ = perform_get_request("/api/photos:get/all")
    expect(result).to eq("get all photos")
  end

  it "correctly processes '-' in urls" do
    router.on("GET", "/photos/get-all-photos", ->(_) { "get all photos" })
    router.on("GET", "/api/photos/get-em/all", ->(_) { "api get all photos" })

    result, _ = perform_get_request("/photos/get-all-photos")
    expect(result).to eq("get all photos")

    result, _ = perform_get_request("/api/photos/get-em/all")
    expect(result).to eq("api get all photos")
  end

  it "raises on duplicates" do
    router.on("GET", "/photos", ->(_) {})
    expect {
      router.on("GET", "/photos", ->(_) {})
    }.to raise_error("Method 'GET' already declared for route '/photos' with constraints '{}'")
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Router::Backend do
  it "correctly processes a constrained url" do
    router.on("GET", "/photos", ->(_) { "get photos" }, constraints: { host: "google.com" })

    result, _ = perform_get_request("/photos")
    expect(result).to be_nil

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("get photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to be_nil
  end

  it "correctly processes urls with multiple constraints" do
    router.on("GET", "/photos", ->(_) { "US photos" }, constraints: { host: "google.com" })
    router.on("GET", "/photos", ->(_) { "CA photos" }, constraints: { host: "google.ca" })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("US photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to eq("CA photos")

    result, _ = perform_get_request("/photos", host: "google.fr")
    expect(result).to be_nil
  end

  it "correctly processes urls with and without constraints" do
    router.on("GET", "/photos", ->(_) { "US photos" }, constraints: { host: "google.com" })
    router.on("GET", "/photos", ->(_) { "all photos" })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("US photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to eq("all photos")
  end

  it "correctly processes regexp host constraints" do
    router.on("GET", "/photos", ->(_) { "g photos" }, constraints: { host: /google/ })
    router.on("GET", "/photos", ->(_) { "y photos" }, constraints: { host: /yahoo/ })
    router.on("GET", "/photos", ->(_) { "all photos" })

    result, _ = perform_get_request("/photos", host: "bing.com")
    expect(result).to eq("all photos")

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("g photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to eq("g photos")

    result, _ = perform_get_request("/photos", host: "yahoo.com")
    expect(result).to eq("y photos")
  end

  it "correctly processes regexp and string host constraints" do
    router.on("GET", "/photos", ->(_) { "regexp photos" }, constraints: { host: /google.(com|ca|fr)/ })
    router.on("GET", "/photos", ->(_) { "string photos" }, constraints: { host: "google.ca" })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("regexp photos")

    result, _ = perform_get_request("/photos", host: "google.fr")
    expect(result).to eq("regexp photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to eq("string photos")
  end

  it "correctly processes subdomain constraints" do
    router.on("GET", "/photos", ->(_) { "regexp photos" }, constraints: { host: /google.ca/ })
    router.on("GET", "/photos", ->(_) { "string photos" }, constraints: { host: "google.ca" })

    result, _ = perform_get_request("/photos", host: "images.google.ca")
    expect(result).to eq("regexp photos")

    result, _ = perform_get_request("/photos", host: "google.ca")
    expect(result).to eq("string photos")
  end

  it "correctly processes regexp host constraints" do
    router.on("GET", "/photos", ->(_) { "photos" }, constraints: { host: /google/ })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("photos")

    result, _ = perform_get_request("/photos", host: "yahoo.com")
    expect(result).to be_nil
  end

  it "correctly processes wildcards with host constraints" do
    router.on("GET", "*", ->(_) { "default" }, constraints: { host: /google/ })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("default")

    result, _ = perform_get_request("/photos", host: "yahoo.com")
    expect(result).to be_nil
  end

  it "correctly processes wildcard urls with host constraints" do
    router.on("GET", "/photos", ->(_) { "photos" }, constraints: { host: /google/ })
    router.on("GET", "*", ->(_) { "default" }, constraints: { host: /google/ })

    result, _ = perform_get_request("/photos", host: "google.com")
    expect(result).to eq("photos")

    result, _ = perform_get_request("/photo", host: "google.com")
    expect(result).to eq("default")
  end

  it "raises in case of unknown constraint" do
    expect {
      router.on("GET", "/photos", ->(_) {}, constraints: { version: "1.0" })
    }.to raise_error("No strategy registered for constraint key 'version'")
  end

  it "raises in case the host constraint uses incorrect value" do
    expect {
      router.on("GET", "/photos", ->(_) {}, constraints: { host: -> {} })
    }.to raise_error("Host should be a string or a Regexp")
  end

  it "raises on duplicates" do
    router.on("GET", "/photos", ->(_) {}, constraints: { host: "google" })
    expect {
      router.on("GET", "/photos", ->(_) {}, constraints: { host: "google" })
    }.to raise_error("Method 'GET' already declared for route '/photos' with constraints '{:host=>\"google\"}'")
  end

  it "correctly sets constraints for urls with optional parameters" do
    router.on("GET", "/photos(/:id)", ->(_) { "optional photo" }, constraints: { host: /yahoo/ })

    result, _ = perform_get_request("/photos")
    expect(result).to be_nil

    result, _ = perform_get_request("/photos/12", host: "google.com")
    expect(result).to be_nil

    result, _ = perform_get_request("/photos", host: "yahoo.com")
    expect(result).to eq("optional photo")

    result, _ = perform_get_request("/photos/13", host: "yahoo.com")
    expect(result).to eq("optional photo")
  end
end

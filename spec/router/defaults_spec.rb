# frozen_string_literal: true

RSpec.describe Rage::Router::Backend do
  it "correctly processes defaults" do
    router.on("GET", "/photos", ->(_) { "all photos" }, defaults: { format: "jpg" })

    result, params = perform_get_request("/photos")
    expect(result).to eq("all photos")
    expect(params).to eq({ format: "jpg" })
  end

  it "correctly processes defaults with parametric urls" do
    router.on("GET", "/photo/:id", ->(_) { "one photo" }, defaults: { format: "jpg" })

    result, params = perform_get_request("/photo/10")
    expect(result).to eq("one photo")
    expect(params).to eq({ id: "10", format: "jpg" })
  end

  it "prioritizes url params over defaults" do
    router.on("GET", "/photo/:id", ->(_) {}, defaults: { id: "20" })

    _, params = perform_get_request("/photo/30")
    expect(params).to eq({ id: "30" })
  end

  it "uses defaults when a parameter is missing" do
    router.on("GET", "/photo(/:id)", ->(_) {}, defaults: { id: "20" })

    _, params = perform_get_request("/photo")
    expect(params).to eq({ id: "20" })

    _, params = perform_get_request("/photo/30")
    expect(params).to eq({ id: "30" })
  end

  it "converts default values to string" do
    router.on("GET", "/photos", ->(_) {}, defaults: { id: 15 })

    _, params = perform_get_request("/photos")
    expect(params).to eq({ id: "15" })
  end

  it "doesn't check defaults when searching for duplicate routes" do
    router.on("GET", "/photos", ->(_) {})
    expect {
      router.on("GET", "/photos", ->(_) {}, defaults: { id: 15 })
    }.to raise_error(/already declared/)
  end
end

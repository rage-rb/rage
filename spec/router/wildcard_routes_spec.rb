# frozen_string_literal: true

RSpec.describe Rage::Router::Backend do
  it "correctly processes a wildcard url" do
    router.on("GET", "/photos/:id/*", ->(_) { "photos with wildcard" })

    result, params = perform_get_request("/photos/1/get-over-here")
    expect(result).to eq("photos with wildcard")
    expect(params).to include({ id: "1", "*": "get-over-here" })
  end

  it "correctly processes a wildcard url" do
    router.on("GET", "/", ->(_) { "root" })
    router.on("GET", "/photos", ->(_) { "photos" })
    router.on("GET", "/*", ->(_) { "root with wildcard" })

    result, _ = perform_get_request("/")
    expect(result).to eq("root")

    result, _ = perform_get_request("/photos")
    expect(result).to eq("photos")

    result, _ = perform_get_request("/not-found")
    expect(result).to eq("root with wildcard")
  end

  it "raises an error if wildcard is not the last character" do
    expect {
      router.on("GET", "/photos/*/print", ->(_) {})
    }.to raise_error("Wildcard must be the last character in the route")
  end

  it "correctly distinguishes between different route types" do
    router.on("GET", "/photos/print", ->(_) { "print all photos" })
    router.on("GET", "/photos/print/:id", ->(_) { "print single photo" })
    router.on("GET", "/photos/*", ->(_) { "photos wildcard" })

    result, _ = perform_get_request("/photos/print")
    expect(result).to eq("print all photos")

    result, _ = perform_get_request("/photos/print/2")
    expect(result).to eq("print single photo")

    result, _ = perform_get_request("/photos/all")
    expect(result).to eq("photos wildcard")

    result, _ = perform_get_request("/get_photos")
    expect(result).to be_nil
  end

  it "correctly distinguishes between different route types" do
    router.on("GET", "/photos/all/print", ->(_) { "print all photos" })
    router.on("GET", "/photos/all/*", ->(_) { "all photos wildcard" })
    router.on("GET", "/photos/:id/print", ->(_) { "print single photo" })

    result, _ = perform_get_request("/photos/all/print")
    expect(result).to eq("print all photos")

    result, params = perform_get_request("/photos/all/24")
    expect(result).to eq("all photos wildcard")
    expect(params).to include({ "*": "24" })

    result, params = perform_get_request("/photos/24/print")
    expect(result).to eq("print single photo")
    expect(params).to include({ id: "24" })

    result, _ = perform_get_request("/photos/24/all")
    expect(result).to be_nil
  end

  it "correctly distinguishes between different methods" do
    router.on("GET", "*", ->(_) { "default" })
    router.on("GET", "/photos/*", ->(_) { "photos wildcard" })

    result, _ = perform_post_request("/photos/1")
    expect(result).to be_nil

    result, _ = perform_post_request("/default")
    expect(result).to be_nil
  end

  it "correctly processes encoded urls" do
    router.on("GET", "/photos/*", ->(_) { "get a photo" })

    result, params = perform_get_request("/photos/get+photos%3B+kind%3A+favorites%3B+type%3D*.jpg")
    expect(result).to eq("get a photo")
    expect(params).to include({ "*": "get photos; kind: favorites; type=*.jpg" })
  end
end

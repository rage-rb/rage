# frozen_string_literal: true

RSpec.describe Rage::Router::Backend do
  it "correctly processes a parametric url" do
    router.on("GET", "/photos/:id", ->(_) { "photo by id" })

    result, params = perform_get_request("/photos/123")
    expect(result).to eq("photo by id")
    expect(params).to eq({ "id" => "123" })
  end

  it "correctly processes a parametric url with multiple sections" do
    router.on("GET", "/api/:version/photos/:id/get", ->(_) { "api photo by id" })

    result, params = perform_get_request("/api/v1/photos/1/get")
    expect(result).to eq("api photo by id")
    expect(params).to eq({ "version" => "v1", "id" => "1" })

    result, _ = perform_get_request("/api/v1/photos/1/set")
    expect(result).to be_nil

    result, params = perform_get_request("/v1/photos/1/get")
    expect(result).to be_nil
  end

  it "correctly processes a parametric url with multiple sections" do
    router.on("GET", "/photos/:id/:user_id", ->(_) { "photo by id and user_id" })

    result, params = perform_get_request("/photos/1/222")
    expect(result).to eq("photo by id and user_id")
    expect(params).to eq({ "id" => "1", "user_id" => "222" })

    result, _ = perform_get_request("/photos/1/222/333")
    expect(result).to be_nil
  end

  it "correctly processes a parametric url with first parameter" do
    router.on("GET", "/:id/get_photos", ->(_) { "get photos" })

    result, params = perform_get_request("/111/get_photos")
    expect(result).to eq("get photos")
    expect(params).to eq({ "id" => "111" })

    result, _ = perform_get_request("/111/get_photo")
    expect(result).to be_nil
  end

  it "correctly processes a parametric url with first parameter" do
    router.on("GET", "/:id/photos/get", ->(_) { "get photos" })

    result, params = perform_get_request("/12/photos/get")
    expect(result).to eq("get photos")
    expect(params).to eq({ "id" => "12" })

    result, _ = perform_get_request("/12/photos")
    expect(result).to be_nil

    result, _ = perform_get_request("/12/photos/set")
    expect(result).to be_nil
  end

  it "correctly processes optional parameters" do
    router.on("GET", "/photos/(:id)", ->(_) { "maybe photo by id" })

    result, params = perform_get_request("/photos")
    expect(result).to eq("maybe photo by id")
    expect(params).to be_empty

    result, params = perform_get_request("/photos/first")
    expect(result).to eq("maybe photo by id")
    expect(params).to eq({ "id" => "first" })
  end

  it "correctly processes optional parameters" do
    router.on("GET", "/photos(/:id)", ->(_) { "maybe photo by id" })

    result, params = perform_get_request("/photos")
    expect(result).to eq("maybe photo by id")
    expect(params).to be_empty

    result, params = perform_get_request("/photos/first")
    expect(result).to eq("maybe photo by id")
    expect(params).to eq({ "id" => "first" })
  end

  it "raises an error if optional param is not the last param" do
    expect {
      router.on("GET", "/photos/(:size)/print", ->(_) {})
    }.to raise_error("Optional Parameter has to be the last parameter of the path")
  end

  it "correctly distinguishes between static and parametric routes" do
    router.on("GET", "/photos/get_all", ->(_) { "get all photos" })
    router.on("GET", "/photos/:id", ->(_) { "photo by id" })
    router.on("GET", "/photos/last", ->(_) { "last photo" })

    result, _ = perform_get_request("/photos/get_all")
    expect(result).to eq("get all photos")

    result, _ = perform_get_request("/photos/2")
    expect(result).to eq("photo by id")

    result, _ = perform_get_request("/photos/last")
    expect(result).to eq("last photo")
  end

  it "correctly processes urls with dots" do
    router.on("GET", "/photos.jpg/:id/get", ->(_) { "jpg photo by id" })

    result, params = perform_get_request("/photos.jpg/2/get")
    expect(result).to eq("jpg photo by id")
    expect(params).to eq({ "id" => "2" })
  end

  it "correctly processes '-' in urls" do
    router.on("GET", "/photos/:id", ->(_) { "get photo by id" })
    router.on("GET", "/api/photos/:id/all", ->(_) { "api get all photos" })

    result, params = perform_get_request("/photos/123-my-favorite-one")
    expect(result).to eq("get photo by id")
    expect(params).to eq({ "id" => "123-my-favorite-one" })

    result, params = perform_get_request("/api/photos/my-favorites/all")
    expect(result).to eq("api get all photos")
    expect(params).to eq({ "id" => "my-favorites" })
  end

  it "correctly processes encoded urls" do
    router.on("GET", "/photos/:id/fetch", ->(_) { "get photo by id" })

    result, params = perform_get_request("/photos/get+photos%3B+kind%3A+favorites%3B+type%3D*.jpg/fetch")
    expect(result).to eq("get photo by id")
    expect(params).to eq({ "id" => "get photos; kind: favorites; type=*.jpg" })
  end

  it "correctly processes '::' in urls" do
    router.on("GET", "/::photos::jpg/:id/::metadata", ->(_) { "get metadata" })
    router.on("GET", "/::photos::jpg/:id/:date", ->(_) { "get photo by id and date" })

    result, params = perform_get_request("/:photos:jpg/23/:metadata")
    expect(result).to eq("get metadata")
    expect(params).to eq({ "id" => "23" })

    result, params = perform_get_request("/:photos:jpg/11/10-10-2020")
    expect(result).to eq("get photo by id and date")
    expect(params).to eq({ "id" => "11", "date" => "10-10-2020" })
  end

  it "correctly processes '%' in urls" do
    router.on("GET", "/photos%jpg/:id", ->(_) { "jpg photo by id" })

    result, params = perform_get_request("/photos%25jpg/3")
    expect(result).to eq("jpg photo by id")
    expect(params).to eq({ "id" => "3" })
  end

  it "correctly processes parametric urls" do
    router.on("GET", "/:namespace/:type/:id", ->(_) { "url 1" })
    router.on("GET", "/:namespace/photos/:id/mark", ->(_) { "url 2" })
    router.on("GET", "/svg/photos/:id/mark", ->(_) { "url 3" })

    result, params = perform_get_request("/jpg/favorites/10")
    expect(result).to eq("url 1")
    expect(params).to eq({ "namespace" => "jpg", "type" => "favorites", "id" => "10" })

    result, params = perform_get_request("/jpg/photos/11/mark")
    expect(result).to eq("url 2")
    expect(params).to eq({ "namespace" => "jpg", "id" => "11" })

    result, params = perform_get_request("/svg/photos/12/mark")
    expect(result).to eq("url 3")
    expect(params).to eq({ "id" => "12" })
  end
end

RSpec.describe Rage::Request do
  let(:env) do
    {
      "rack.upgrade?" => nil,
      "rack.upgrade" => nil,
      "rack.version" => [1, 3],
      "SCRIPT_NAME" => "",
      "rack.url_scheme" => "http",
      "HTTP_VERSION" => "HTTP/1.1",
      "PATH_INFO" => "/users",
      "QUERY_STRING" => "show_archived=true",
      "REMOTE_ADDR" => "::1",
      "REQUEST_METHOD" => "GET",
      "SERVER_NAME" => "localhost",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "IODINE_REQUEST_ID" => "QUERY_STRING",
      "IODINE_HAS_BODY" => false,
      "SERVER_PORT" => "3000",
      "HTTP_HOST" => "localhost:3000",
      "HTTP_CONNECTION" => "keep-alive",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; ...",
      "HTTP_ACCEPT" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
      "HTTP_ACCEPT_ENCODING" => "gzip, deflate, br, zstd",
      "HTTP_ACCEPT_LANGUAGE" => "en-GB,en-US;q=0.9,en;q=0.8",
      "HTTP_COOKIE" => "test_cookie=1"
    }
  end

  subject(:request) { described_class.new(env) }

  it "returns the full URL" do
    expect(request.url).to eq("http://localhost:3000/users?show_archived=true")
  end

  it "returns the path" do
    expect(request.path).to eq("/users")
  end

  it "returns the full path with query string" do
    expect(request.fullpath).to eq("/users?show_archived=true")
  end

  it "returns the user agent" do
    expect(request.user_agent).to eq("Mozilla/5.0 (Macintosh; ...")
  end

  it "handles default ports in URL" do
    env["SERVER_PORT"] = "80"
    expect(request.url).to eq("http://localhost/users?show_archived=true")

    env["rack.url_scheme"] = "https"
    env["SERVER_PORT"] = "443"
    expect(request.url).to eq("https://localhost/users?show_archived=true")
  end

  it "handles empty query string in full path" do
    env["QUERY_STRING"] = ""
    expect(request.fullpath).to eq("/users")
  end

  it "handles missing user agent header" do
    env.delete("HTTP_USER_AGENT")
    expect(request.user_agent).to be_nil
  end
end

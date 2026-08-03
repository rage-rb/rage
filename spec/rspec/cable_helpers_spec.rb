# frozen_string_literal: true

require "domain_name"

begin
  require "rbnacl"
  RBNACL_AVAILABLE = Gem::Version.create(RbNaCl::VERSION) >= Gem::Version.create("3.3.0") &&
                     Gem::Version.create(RbNaCl::VERSION) < Gem::Version.create("8.0.0")
rescue LoadError
  RBNACL_AVAILABLE = false
end

module CableRspecHelpersSpec
  class TestConnection < Rage::Cable::Connection
    identified_by :user_id

    def connect
      if (header_user_id = request.headers["X-USER-ID"])
        self.user_id = header_user_id
      elsif (cookie_user_id = cookies[:user_id])
        self.user_id = cookie_user_id
      elsif (encrypted_user_id = cookies.encrypted[:encrypted_user_id])
        self.user_id = encrypted_user_id
      elsif (session_user_id = session[:user_id])
        self.user_id = session_user_id
      else
        reject_unauthorized_connection
      end
    end
  end

  class TestChannel < Rage::Cable::Channel
    def subscribed
      if params[:room_id] == -1
        reject
      elsif params[:room_id]
        stream_from("chat_#{params[:room_id]}")
      end
    end

    def speak(data)
      transmit({ text: data["message"] })
    end
  end

  Room = Struct.new(:id)

  class StreamForChannel < Rage::Cable::Channel
    def subscribed
      stream_for(params[:room])
    end
  end
end

RSpec.shared_context "rage cable test helpers setup" do
  before :context do
    Rage.instance_variable_set(:@root, Pathname.new(__dir__).expand_path)
    Rage.instance_variable_set(:@env, Rage::Env.new("test"))
    require "rage/rspec"

    @original_secret_key_base = Rage.config.secret_key_base
    Rage.config.secret_key_base = "a" * 128
  end

  after :context do
    Rage.config.secret_key_base = @original_secret_key_base
    Rage.instance_variable_set(:@root, nil)
    Rage.instance_variable_set(:@env, nil)
  end
end

RSpec.describe CableRspecHelpersSpec::TestConnection, type: :channel do
  include_context "rage cable test helpers setup"

  it "emulates a connection with headers" do
    connect "/cable", headers: { "X-USER-ID" => "325" }

    expect(connection.user_id).to eq("325")
  end

  it "supports encrypted cookies", if: RBNACL_AVAILABLE do
    cookies.encrypted[:encrypted_user_id] = "42"
    connect "/cable"

    expect(connection.user_id).to eq("42")
  end

  it "supports plain cookies" do
    cookies[:user_id] = "24"
    connect "/cable"

    expect(connection.user_id).to eq("24")
  end

  it "supports session data", if: RBNACL_AVAILABLE do
    session[:user_id] = "17"
    connect "/cable"

    expect(connection.user_id).to eq("17")
  end

  it "exposes rejection state" do
    connect "/cable"

    expect(connection).to be_rejected
  end
end

RSpec.describe CableRspecHelpersSpec::TestChannel, type: :channel do
  include_context "rage cable test helpers setup"

  before do
    stub_connection user_id: 123
  end

  it "subscribes without streams when no room id is provided" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).not_to have_streams
  end

  it "rejects subscription for an invalid room id" do
    subscribe(room_id: -1)

    expect(subscription).to be_rejected
  end

  it "tracks stream subscriptions" do
    subscribe(room_id: 42)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("chat_42")
    expect(subscription.streams).to eq(["chat_42"])
  end

  it "performs channel actions and captures transmissions" do
    subscribe(room_id: 42)
    perform :speak, message: "Hello!"

    expect(transmissions.last["text"]).to eq("Hello!")
  end

  it "hides internals in expectation output for mock subscription objects" do
    subscribe(room_id: -1)

    expect {
      expect(subscription).not_to be_rejected
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError) { |error|
      expect(error.message).to include("#<RageCableHelpers::MockSubscription>")
      expect(error.message).not_to include("@__")
    }
  end
end

RSpec.describe CableRspecHelpersSpec::StreamForChannel, type: :channel do
  include_context "rage cable test helpers setup"

  before do
    stub_connection user_id: 123
  end

  it "supports stream_for assertions" do
    room = CableRspecHelpersSpec::Room.new(42)

    subscribe(room: room)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(room)
  end
end

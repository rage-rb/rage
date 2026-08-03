# frozen_string_literal: true

require "rack/test"
require "json"
require "uri"
require "digest"

# set up environment
ENV["RAGE_ENV"] ||= "test"

# load the app
require "bundler/setup"
require "rage"
require_relative "#{Rage.root}/config/application"

# verify the environment
abort("The test suite is running in #{Rage.env} mode instead of 'test'!") unless Rage.env.test?

# define request helpers
module RageRequestHelpers
  include Rack::Test::Methods

  alias_method :response, :last_response

  APP = Rack::Builder.parse_file("#{Rage.root}/config.ru").yield_self do |app|
    app.is_a?(Array) ? app[0] : app
  end

  def app
    APP
  end

  %w(get options head).each do |method_name|
    class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def #{method_name}(path, params: {}, headers: {})
        request("#{method_name.upcase}", path, params: params, headers: headers)
      end
    RUBY
  end

  %w(post put patch delete).each do |method_name|
    class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def #{method_name}(path, params: {}, headers: {}, as: nil)
        if as == :json
          params = params.to_json
          headers["content-type"] = "application/json"
        end

        request("#{method_name.upcase}", path, params: params, headers: headers.merge("IODINE_HAS_BODY" => !params.empty?))
      end
    RUBY
  end

  def request(method, path, params: {}, headers: {})
    headers = __normalize_rack_headers(headers)
    custom_request(method, path, params, headers)
  end

  def host!(host)
    @__host = host
  end

  def default_host
    @__host || "example.org"
  end

  private

  def __normalize_rack_headers(headers)
    return {} if headers.nil? || headers.empty?

    headers.transform_keys do |key|
      key = key.to_s

      if key.downcase == "content-type"
        "CONTENT_TYPE"
      elsif key.downcase == "content-length"
        "CONTENT_LENGTH"
      elsif key == "CONTENT_TYPE" || key == "CONTENT_LENGTH" || key.start_with?("HTTP_") || (key == key.upcase && key.include?("_") && !key.include?("-"))
        key
      else
        "HTTP_#{key.tr("-", "_").upcase}"
      end
    end
  end
end

module RageCableHelpers
  include RageRequestHelpers

  class MockWebSocketConnection
    attr_reader :env, :messages

    def initialize(env)
      @env = env
      @messages = []
      @streams = []
    end

    def subscribe(stream)
      @streams << stream.sub(/\Acable:/, "").sub(/:[0-9a-f]{32}\z/, "")
      true
    end

    def write(data)
      @messages << data
      true
    end

    def close
      true
    end

    def streams
      @streams.uniq
    end
  end

  class MockSubscription
    attr_reader :channel, :connection

    def initialize(channel, connection)
      @channel = channel
      @connection = connection
    end

    def confirmed?
      !channel.subscription_rejected?
    end

    def rejected?
      channel.subscription_rejected?
    end

    def streams
      connection.streams
    end

    def has_streams?
      streams.any?
    end

    def has_stream_from?(stream_name)
      streams.include?(stream_name)
    end

    def has_stream_for?(streamable)
      has_stream_from?(channel.class.__stream_name_for(streamable))
    end

    def inspect
      "#<#{self.class.name}>"
    end

    def method_missing(method_name, *args, &block)
      if channel.respond_to?(method_name)
        channel.public_send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      channel.respond_to?(method_name, include_private) || super
    end
  end

  class MockCookies
    def initialize(context, modifiers = [])
      @context = context
      @modifiers = modifiers
    end

    def [](key)
      jar, = build_jar
      jar[key]
    end

    def []=(key, value)
      jar, headers = build_jar
      jar[key] = value
      merge_set_cookie_header(headers)
      value
    end

    def delete(*args, **kwargs)
      jar, headers = build_jar
      result = jar.delete(*args, **kwargs)
      merge_set_cookie_header(headers)
      result
    end

    def encrypted
      self.class.new(@context, @modifiers + [:encrypted])
    end

    def permanent
      self.class.new(@context, @modifiers + [:permanent])
    end

    private

    def build_jar
      uri = @context.send(:__cable_cookie_uri)
      env = {
        "HTTP_COOKIE" => @context.current_session.cookie_jar.for(uri),
        "HTTP_HOST" => @context.default_host
      }
      headers = {}

      jar = Rage::Cookies.new(env, headers)
      @modifiers.each { |modifier| jar = jar.public_send(modifier) }

      [jar, headers]
    end

    def merge_set_cookie_header(headers)
      set_cookie = headers["set-cookie"]
      return unless set_cookie

      @context.set_cookie(set_cookie, @context.send(:__cable_cookie_uri))
    end
  end

  def cookies
    @__cable_cookies ||= MockCookies.new(self)
  end

  def session
    @__cable_session ||= Rage::Session.new(cookies)
  end

  def connect(url, headers: nil)
    env = __build_cable_env(url, headers || {})
    @__cable_connection = __connection_class.new(env)
    @__cable_connection.connect

    unless @__cable_connection.rejected?
      env["rage.identified_by"] = @__cable_connection.__identified_by_map
      env["rage.cable"] = {}
    end

    @__cable_connection
  end

  def connection
    raise "No connection found. Call `connect` before `connection`." unless @__cable_connection
    @__cable_connection
  end

  def stub_connection(identified_by = {})
    @__cable_stubbed_connection = MockWebSocketConnection.new({
      "rage.cable" => {},
      "rage.identified_by" => identified_by.transform_keys(&:to_sym)
    })
  end

  def subscribe(params = {})
    __stub_cable_protocol!
    __stub_iodine_defer!

    channel_class = __channel_class
    channel_class.__register_actions

    params = (params || {}).each_with_object({}) { |(k, v), memo| memo[k.to_sym] = v }
    params[:channel] = channel_class.name

    cable_connection = @__cable_stubbed_connection || stub_connection
    channel = channel_class.new(cable_connection, params, cable_connection.env["rage.identified_by"])
    channel.__run_action(:subscribed)

    unless channel.subscription_rejected?
      cable_connection.env["rage.cable"][params.to_json] = channel
    end

    @__subscription = MockSubscription.new(channel, cable_connection)
  end

  def subscription
    raise "No subscription found. Call `subscribe` before `subscription`." unless @__subscription
    @__subscription
  end

  def perform(action, data = {})
    raise "No subscription found. Call `subscribe` before `perform`." unless subscription

    payload = (data || {}).each_with_object({ "action" => action.to_s }) do |(key, value), memo|
      memo[key.to_s] = value
    end
    action_name = action.to_sym

    unless subscription.channel.__has_action?(action_name)
      raise ArgumentError, "Unable to process #{subscription.channel.class.name}##{action_name}"
    end

    subscription.channel.__run_action(action_name, payload)
  end

  def transmissions
    return [] unless subscription

    subscription.connection.messages.map do |message|
      parsed_message = begin
        JSON.parse(message)
      rescue JSON::ParserError, TypeError
        message
      end

      if parsed_message.is_a?(Hash)
        parsed_message["message"] || parsed_message[:message] || parsed_message
      else
        parsed_message
      end
    end
  end

  private

  def __build_cable_env(url, headers)
    uri = URI.parse(url)
    uri.path = "/#{uri.path}" unless uri.path.start_with?("/")
    uri.host ||= default_host
    uri.scheme ||= "http"

    env = Rack::MockRequest.env_for(uri.to_s, __normalize_rack_headers(headers))
    env["REQUEST_METHOD"] = "GET"

    cookie_header = current_session.cookie_jar.for(uri)
    env["HTTP_COOKIE"] = cookie_header unless cookie_header.empty?

    env
  end

  def __connection_class
    if respond_to?(:described_class) && described_class.is_a?(Class) && described_class <= Rage::Cable::Connection
      described_class
    elsif Object.const_defined?("RageCable::Connection")
      RageCable::Connection
    elsif Object.const_defined?("ApplicationCable::Connection")
      ApplicationCable::Connection
    else
      Rage::Cable::Connection
    end
  end

  def __channel_class
    if !respond_to?(:described_class) || !described_class.is_a?(Class) || !described_class.ancestors.include?(Rage::Cable::Channel)
      raise ArgumentError, "`subscribe` expects the described class to inherit from Rage::Cable::Channel"
    end

    described_class
  end

  def __cable_cookie_uri
    URI.parse("http://#{default_host}/")
  end

  def __stub_cable_protocol!
    allow(Rage.cable).to receive(:__protocol).and_return(__cable_test_protocol)
  end

  def __stub_iodine_defer!
    allow(Iodine).to receive(:defer) do |&block|
      block&.call
      true
    end
  end

  def __cable_test_protocol
    @__cable_test_protocol ||= Class.new do
      def supports_rpc?
        true
      end

      def subscribe(connection, stream, params)
        stream_id = Digest::MD5.hexdigest(params.to_s)
        connection.subscribe("cable:#{stream}:#{stream_id}")
      end

      def broadcast(*)
      end

      def serialize(params, data)
        { identifier: params.to_json, message: data }.to_json
      end
    end.new
  end
end

# include request helpers
RSpec.configure do |config|
  config.include(RageRequestHelpers, type: :request)
  config.include(RageCableHelpers, type: :channel)

  # mock fiber methods as RSpec tests don't run concurrently
  config.before do
    allow(Fiber).to receive(:schedule) do |&block|
      fiber = Fiber.new(blocking: true) do
        Fiber.current.__set_id
        Fiber.current.__set_result(block.call)
      end
      fiber.resume

      fiber
    end

    allow(Fiber).to receive(:await) do |fibers|
      Array(fibers).map(&:__get_result)
    end
  end
end

# patch MockResponse class
class Rack::MockResponse
  def parsed_body
    if headers["content-type"]&.start_with?("application/json")
      JSON.parse(body)
    else
      body
    end
  end

  def code
    status.to_s
  end

  alias_method :response_code, :status
end

# define http status matcher
RSpec::Matchers.matcher :have_http_status do |expected|
  codes = Rack::Utils::SYMBOL_TO_STATUS_CODE

  failure_message do |response|
    actual = response.status

    if expected.is_a?(Integer)
      "expected the response to have status code #{expected} but it was #{actual}"
    elsif expected == :success
      "expected the response to have a success status code (2xx) but it was #{actual}"
    elsif expected == :error
      "expected the response to have an error status code (5xx) but it was #{actual}"
    elsif expected == :missing
      "expected the response to have a missing status code (404) but it was #{actual}"
    else
      "expected the response to have status code :#{expected} (#{codes[expected]}) but it was :#{codes.key(actual)} (#{actual})"
    end
  end

  failure_message_when_negated do |response|
    actual = response.status

    if expected.is_a?(Integer)
      "expected the response not to have status code #{expected} but it was #{actual}"
    elsif expected == :success
      "expected the response not to have a success status code (2xx) but it was #{actual}"
    elsif expected == :error
      "expected the response not to have an error status code (5xx) but it was #{actual}"
    elsif expected == :missing
      "expected the response not to have a missing status code (404) but it was #{actual}"
    else
      "expected the response not to have status code :#{expected} (#{codes[expected]}) but it was :#{codes.key(actual)} (#{actual})"
    end
  end

  match do |response|
    actual = response.status

    case expected
    when :success
      actual >= 200 && actual < 300
    when :error
      actual >= 500
    when :missing
      actual == 404
    when Symbol
      actual == codes.fetch(expected)
    else
      actual == expected
    end
  end
end

if defined? RSpec::Rails::Matchers
  module RSpec::Rails::Matchers
    def have_http_status(_)
      super
    end
  end
end

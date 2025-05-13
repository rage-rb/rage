# frozen_string_literal: true

require "rack/test"
require "json"

# set up environment
ENV["RAGE_ENV"] ||= "test"

# load the app
require "bundler/setup"
require "rage"
require_relative "#{Rage.root}/config/application"

# verify the environment
abort("The test suite is running in #{Rage.env} mode instead of 'test'!") unless Rage.env.test?

# mock fiber methods as RSpec tests don't run concurrently
class Fiber
  def self.schedule(&block)
    fiber = Fiber.new(blocking: true) do
      Fiber.current.__set_id
      Fiber.current.__set_result(block.call)
    end
    fiber.resume

    fiber
  end

  def self.await(fibers)
    Array(fibers).map(&:__get_result)
  end
end

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
    if headers.any?
      headers = headers.transform_keys do |k|
        if k.downcase == "content-type"
          "CONTENT_TYPE"
        elsif k.downcase == "content-length"
          "CONTENT_LENGTH"
        elsif k.upcase == k
          k
        else
          "HTTP_#{k.tr("-", "_").upcase! || k}"
        end
      end
    end

    custom_request(method, path, params, headers)
  end

  def host!(host)
    @__host = host
  end

  def default_host
    @__host || "example.org"
  end
end

# include request helpers
RSpec.configure do |config|
  config.include(RageRequestHelpers, type: :request)
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

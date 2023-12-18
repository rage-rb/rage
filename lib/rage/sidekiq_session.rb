# frozen_string_literal: true

require "digest"
require "base64"

##
# Used **specifically** for compatibility with Sidekiq's Web interface.
# Remove once we have real sessions or once Sidekiq's author decides they
# don't need cookie sessions to protect against CSRF.
#
class Rage::SidekiqSession
  KEY = Digest::SHA2.hexdigest(ENV["SECRET_KEY_BASE"] || File.read("Gemfile.lock") + File.read("config/routes.rb"))
  SESSION_KEY = "rage.sidekiq.session"

  def self.with_session(env)
    env["rack.session"] = session = self.new(env)
    response = yield

    if session.changed
      Rack::Utils.set_cookie_header!(
        response[1],
        SESSION_KEY,
        { path: env["SCRIPT_NAME"], httponly: true, same_site: true, value: session.dump }
      )
    end

    response
  end

  attr_reader :changed

  def initialize(env)
    @env = env
    session = Rack::Utils.parse_cookies(@env)[SESSION_KEY]
    @data = decode_session(session)
  end

  def [](key)
    @data[key]
  end

  def[]=(key, value)
    @changed = true
    @data[key] = value
  end

  def to_hash
    @data
  end

  def dump
    encoded_data = Marshal.dump(@data)
    signature = OpenSSL::HMAC.hexdigest("SHA256", KEY, encoded_data)

    Base64.urlsafe_encode64("#{encoded_data}--#{signature}")
  end

  private

  def decode_session(session)
    return {} unless session

    encoded_data, signature = Base64.urlsafe_decode64(session).split("--")
    ref_signature = OpenSSL::HMAC.hexdigest("SHA256", KEY, encoded_data)

    if Rack::Utils.secure_compare(signature, ref_signature)
      Marshal.load(encoded_data)
    else
      {}
    end
  end
end

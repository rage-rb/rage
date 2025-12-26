# frozen_string_literal: true

require "json"

##
# Sessions securely store data between requests using cookies and are typically one of the most convenient and secure
# authentication mechanisms for browser-based clients.
#
# Rage sessions are encrypted using a secret key. This prevents clients from reading or tampering with session data.
#
# ## Setup
#
# 1. Add the required gems to your `Gemfile`:
#
#     ```bash
#     bundle add base64 domain_name rbnacl
#     ```
#
# 2. Generate a secret key base (keep this value private and out of version control):
#
#     ```bash
#     ruby -r securerandom -e 'puts SecureRandom.hex(64)'
#     ```
#
# 3. Configure your application to use the generated key, either via configuration:
#
#     ```ruby
#     Rage.configure do |config|
#       config.secret_key_base = "my-secret-key"
#     end
#     ```
#
#     or via the `SECRET_KEY_BASE` environment variable:
#
#     ```bash
#     export SECRET_KEY_BASE="my-secret-key"
#     ```
#
# ## System Dependencies
#
# Rage sessions use libsodium (via RbNaCl) for encryption. On many Debian-based systems
# it is installed by default; if not, install it with:
#
# - Ubuntu / Debian:
#
#     ```bash
#     sudo apt install libsodium23
#     ```
#
# - Fedora / RHEL / Amazon Linux:
#
#     ```bash
#     sudo yum install libsodium
#     ```
#
# - macOS (using Homebrew):
#
#     ```bash
#     brew install libsodium
#     ```
#
class Rage::Session
  # @private
  def self.key
    @key ||= :"_#{Rage.root.basename.to_s.gsub(/\W/, "_").downcase}_session"
  end

  # @private
  def initialize(cookies)
    @cookies = cookies.encrypted
  end

  # Writes the value to the session.
  #
  # @param key [Symbol]
  # @param value [String]
  def []=(key, value)
    write_session(add: { key => value })
  end

  # Returns the value of the key stored in the session or `nil` if the given key is not found.
  #
  # @param key [Symbol]
  def [](key)
    read_session[key]
  end

  # Returns the value of the given key from the session, or raises `KeyError` if the given key is not found
  # and no default value is set. Returns the default value if specified.
  #
  # @param key [Symbol]
  def fetch(key, default = nil, &block)
    if default.nil?
      read_session.fetch(key, &block)
    else
      read_session.fetch(key, default, &block)
    end
  end

  # Deletes the given key from the session.
  #
  # @param key [Symbol]
  def delete(key)
    write_session(remove: key)
  end

  # Clears the session.
  def clear
    write_session(clear: true)
  end

  # Returns the session as Hash.
  def to_hash
    read_session
  end

  alias_method :to_h, :to_hash

  def empty?
    read_session.empty?
  end

  # Returns `true` if the given key is present in the session.
  def has_key?(key)
    read_session.has_key?(key)
  end

  alias_method :key?, :has_key?
  alias_method :include?, :has_key?

  def each(&block)
    read_session.each(&block)
  end

  def dig(*keys)
    read_session.dig(*keys)
  end

  def inspect
    "#<#{self.class.name} @session=#{to_h.inspect}"
  end

  private

  def write_session(add: nil, remove: nil, clear: nil)
    if add
      read_session.merge!(add)
    elsif remove && read_session.has_key?(remove)
      read_session.reject! { |k, _| k == remove }
    elsif clear
      read_session.clear
    end

    @cookies[self.class.key] = { httponly: true, same_site: :lax, value: read_session.to_json }
  end

  def read_session
    @session ||= begin
      session_value = @cookies[self.class.key] || @cookies[Rack::RACK_SESSION.to_sym] || "{}"
      JSON.parse(session_value, symbolize_names: true)
    rescue JSON::ParserError
      {}
    end
  end
end

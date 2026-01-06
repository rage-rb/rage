# frozen_string_literal: true

require "base64"
require "time"

if !defined?(DomainName)
  fail <<~ERR

    rage-rb depends on domain_name to specify the domain name for cookies. Add the following line to your Gemfile:
    gem "domain_name"

  ERR
end

##
# Cookies provide a convenient way to store small amounts of data on the client side that persists across requests.
# They are commonly used for session management, personalization, and tracking user preferences.
#
# Rage cookies support both simple string-based cookies and encrypted cookies for sensitive data.
#
# To use cookies, add the `domain_name` gem to your `Gemfile`:
#
# ```bash
# bundle add domain_name
# ```
#
# Additionally, if you need to use encrypted cookies, see {Session} for setup steps.
#
# ## Usage
#
# ### Basic Cookies
#
# Read and write simple string values:
#
# ```ruby
# # Set a cookie
# cookies[:user_name] = "Alice"
#
# # Read a cookie
# cookies[:user_name] # => "Alice"
#
# # Delete a cookie
# cookies.delete(:user_name)
# ```
#
# ### Cookie Options
#
# Set cookies with additional options for security and control:
#
# ```ruby
# cookies[:user_id] = {
#   value: "12345",
#   expires: 1.year.from_now,
#   secure: true,
#   httponly: true,
#   same_site: :lax
# }
# ```
#
# ### Encrypted Cookies
#
# Store sensitive data securely with automatic encryption:
#
# ```ruby
# # Set an encrypted cookie
# cookies.encrypted[:api_token] = "secret-token"
#
# # Read an encrypted cookie
# cookies.encrypted[:api_token] # => "secret-token"
#
# ```
#
# ### Permanent Cookies
#
# Create cookies that expire 20 years from now:
#
# ```ruby
# cookies.permanent[:remember_token] = "token-value"
#
# # Can be combined with encrypted
# cookies.permanent.encrypted[:user_id] = current_user.id
# ```
#
# ### Domain Configuration
#
# Control which domains can access your cookies:
#
# ```ruby
# # Specific domain
# cookies[:cross_domain] = { value: "data", domain: "example.com" }
#
# # All subdomains
# cookies[:shared] = { value: "data", domain: :all }
#
# # Multiple allowed domains
# cookies[:limited] = { value: "data", domain: ["app.example.com", "api.example.com"] }
# ```
#
# @see Session
#
class Rage::Cookies
  # @private
  def initialize(env, headers)
    @env = env
    @headers = headers
    @request_cookies = {}
    @parsed = false

    @jar = SimpleJar
  end

  # Read a cookie.
  #
  # @param key [Symbol]
  # @return [String]
  def [](key)
    value = request_cookies[key]
    @jar.load(value) if value
  end

  # Get the number of cookies.
  #
  # @return [Integer]
  def size
    request_cookies.count { |_, v| !v.nil? }
  end

  # Delete a cookie.
  #
  # @param key [Symbol]
  # @param path [String]
  # @param domain [String]
  def delete(key, path: "/", domain: nil)
    @request_cookies[key] = nil
    Rack::Utils.delete_cookie_header!(@headers, key, { path: path, domain: domain })
  end

  # Returns a jar that'll automatically encrypt cookie values before sending them to the client and will decrypt them
  # for read. If the cookie was tampered with by the user (or a 3rd party), `nil` will be returned.
  #
  # This jar requires that you set a suitable secret for the verification on your app's `secret_key_base`.
  #
  # @example
  #   cookies.encrypted[:user_id] = current_user.id
  def encrypted
    dup.tap { |c| c.jar = EncryptedJar }
  end

  # Returns a jar that'll automatically set the assigned cookies to have an expiration date 20 years from now.
  #
  # @example
  #   cookies.permanent[:user_id] = current_user.id
  def permanent
    dup.tap { |c| c.expires = Date.today.next_year(20) }
  end

  # Set a cookie.
  #
  # @param key [Symbol]
  # @param value [String, Hash]
  # @option value [String] :path
  # @option value [Boolean] :secure
  # @option value [Boolean] :httponly
  # @option value [nil, :none, :lax, :strict] :same_site
  # @option value [Time] :expires
  # @option value [String, Array<String>, :all] :domain
  # @option value [String] :value
  # @example
  #   cookie[:user_id] = current_user.id
  # @example
  #   cookie[:user_id] = { value: current_user.id, httponly: true, secure: true }
  def []=(key, value)
    unless value.is_a?(Hash)
      serialized_value = @jar.dump(value)
      @request_cookies[key] = serialized_value
      Rack::Utils.set_cookie_header!(@headers, key, { value: serialized_value, expires: @expires })
      return
    end

    if (domain = value[:domain])
      host = @env["HTTP_HOST"]

      processed_domain = if domain.is_a?(String)
        domain
      elsif domain == :all
        DomainName(host).domain
      elsif domain.is_a?(Array)
        host if domain.include?(host)
      end
    end

    serialized_value = @jar.dump(value[:value])
    Rack::Utils.set_cookie_header!(@headers, key, {
      **value,
      value: serialized_value,
      domain: processed_domain,
      expires: value[:expires] || @expires
    })
    @request_cookies[key] = serialized_value
  end

  def inspect
    cookies = request_cookies.transform_values do |v|
      decoded = Base64.urlsafe_decode64(v) rescue nil
      is_encrypted = decoded&.start_with?(EncryptedJar::PADDING)

      is_encrypted ? "<encrypted>" : v
    end

    "#<#{self.class.name} @request_cookies=#{cookies.inspect}"
  end

  private

  def request_cookies
    return @request_cookies if @parsed

    @parsed = true
    if (cookie_header = @env["HTTP_COOKIE"])
      cookie_header.split(/; */n).each do |cookie|
        next if cookie.empty?
        key, value = cookie.split("=", 2).yield_self { |k, _| [k.to_sym, _] }
        unless @request_cookies.has_key?(key)
          @request_cookies[key] = (Rack::Utils.unescape(value, Encoding::UTF_8) rescue value)
        end
      end
    end

    @request_cookies
  end

  protected

  attr_writer :jar, :expires

  ####################
  #
  # Cookie Jars
  #
  ####################

  class SimpleJar
    def self.load(_)
      _
    end

    def self.dump(value)
      value.to_s
    end
  end

  class EncryptedJar
    SALT = "encrypted cookie"
    PADDING = "00"

    class << self
      def load(value)
        box = primary_box

        begin
          box.decrypt(Base64.urlsafe_decode64(value).byteslice(2..))
        rescue ArgumentError
          Rage.logger.debug("Failed to decode encrypted cookie")
          nil
        rescue RbNaCl::CryptoError
          Rage.logger.debug("Failed to decrypt encrypted cookie")
          i ||= 0
          if (box = fallback_boxes[i])
            Rage.logger.debug("Trying to decrypt with fallback key ##{i + 1}")
            i += 1
            retry
          end
        end
      end

      def dump(value)
        # add two bytes to hold meta information, e.g. in case we
        # need to change the encryption algorithm in the future
        Base64.urlsafe_encode64(PADDING + primary_box.encrypt(value.to_s))
      end

      private

      def primary_box
        @primary_box ||= begin
          if !defined?(RbNaCl) || !(Gem::Version.create(RbNaCl::VERSION) >= Gem::Version.create("3.3.0") && Gem::Version.create(RbNaCl::VERSION) < Gem::Version.create("8.0.0"))
            fail <<~ERR

              rage-rb depends on rbnacl [>= 3.3, < 8.0] to encrypt cookies. Add the following line to your Gemfile:
              gem "rbnacl"

            ERR
          end

          unless Rage.config.secret_key_base
            raise "Rage.config.secret_key_base should be set to use encrypted cookies"
          end

          RbNaCl::SimpleBox.from_secret_key(
            RbNaCl::Hash.blake2b(Rage.config.secret_key_base, digest_size: 32, salt: SALT)
          )
        end
      end

      def fallback_boxes
        @fallback_boxes ||= Rage.config.fallback_secret_key_base.map do |key|
          RbNaCl::SimpleBox.from_secret_key(RbNaCl::Hash.blake2b(key, digest_size: 32, salt: SALT))
        end
      end
    end # class << self
  end
end

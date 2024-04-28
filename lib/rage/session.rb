# frozen_string_literal: true

require "json"

class Rage::Session
  # @private
  KEY = Rack::RACK_SESSION.to_sym

  # @private
  def initialize(controller)
    @cookies = controller.cookies.encrypted
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
    read_session[key] || default
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
    read_session.any?
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

    @cookies[KEY] = { httponly: true, same_site: :lax, value: read_session.to_json }
  end

  def read_session
    @session ||= begin
      JSON.parse(@cookies[KEY] || "{}", symbolize_names: true)
    rescue JSON::ParserError
      {}
    end
  end
end

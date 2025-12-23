# frozen_string_literal: true

class Rage::Cable::Connection
  # @private
  attr_reader :__identified_by_map

  # Mark a key as being a connection identifier index that can then be used to find the specific connection again later.
  # Common identifiers are `current_user` and `current_account`, but could be anything.
  #
  # @param identifiers [Symbol,Array<Symbol>]
  def self.identified_by(*identifiers)
    identifiers.each do |method_name|
      define_method(method_name) do
        @__identified_by_map[method_name]
      end

      define_method("#{method_name}=") do |data|
        @__identified_by_map[method_name] = data
      end

      Rage::Cable::Channel.__prepare_id_method(method_name)
    end
  end

  # @private
  def initialize(env, identified_by = {})
    @__env = env
    @__identified_by_map = identified_by
  end

  # @private
  def connect
  end

  # @private
  def disconnect
  end

  # Reject the WebSocket connection.
  def reject_unauthorized_connection
    @rejected = true
  end

  def rejected?
    !!@rejected
  end

  # Get the request object. See {Rage::Request}.
  #
  # @return [Rage::Request]
  def request
    @__request ||= Rage::Request.new(@__env)
  end

  # Get the cookie object. See {Rage::Cookies}.
  #
  # @return [Rage::Cookies]
  def cookies
    @__cookies ||= Rage::Cookies.new(@__env, ReadOnlyHash.new)
  end

  # Get the session object. See {Rage::Session}.
  #
  # @return [Rage::Session]
  def session
    @__session ||= Rage::Session.new(cookies)
  end

  # Get URL query parameters.
  #
  # @return [Hash{Symbol=>String,Array,Hash}]
  def params
    @__params ||= Iodine::Rack::Utils.parse_nested_query(@__env["QUERY_STRING"])
  end

  # @private
  class ReadOnlyHash < Hash
    def []=(_, _)
      raise "Cookies cannot be set for WebSocket clients"
    end
  end
end

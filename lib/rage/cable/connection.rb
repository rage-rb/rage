# frozen_string_literal: true

class Rage::Cable::Connection
  # @private
  attr_reader :__identified_by_map

  class << self
    # @private
    attr_reader :__identifiers
  end

  # Mark a key as being a connection identifier index that can then be used to find the specific connection again later.
  # Common identifiers are `current_user` and `current_account`, but could be anything.
  #
  # @param identifiers [Symbol,Array<Symbol>]
  def self.identified_by(*identifiers)
    identifiers.each do |method_name|
      raise ArgumentError, "Identifier must be a Symbol" unless method_name.is_a?(Symbol)

      (@__identifiers ||= []) << method_name

      define_method(method_name) do
        @__identified_by_map[method_name]
      end

      define_method("#{method_name}=") do |data|
        @__identified_by_map[method_name] = data if data
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

  # @private
  def __connect(connection, protocol)
    Rage::Telemetry.tracer.span_cable_connection_process(connection: self, action: :connect, env: @__env) do
      connect
    end

    __remote_disconnect_setup(connection, protocol) if !rejected? && is_a?(Rage::Cable::RemoteDisconnect)
  end

  # @private
  def __disconnect(connection)
    Rage::Telemetry.tracer.span_cable_connection_process(connection: self, action: :disconnect, env: @__env) do
      disconnect
    end

    __remote_disconnect_cleanup(connection) if is_a?(Rage::Cable::RemoteDisconnect)
  end

  # Disconnect all connections matching the specified identifier.
  #
  # Only one identifier can be provided per call. To disconnect connections matching multiple
  # criteria, define a composite identifier.
  #
  # @note This method is only available when {Rage::Cable::RemoteDisconnect Rage::Cable::RemoteDisconnect} is
  #   included in your connection class.
  #
  # @example Disconnect all connections for a user
  #   RageCable::Connection.disconnect(current_user: User.find(1))
  #
  # @example Using a composite identifier
  #   class RageCable::Connection < Rage::Cable::Connection
  #     include Rage::Cable::RemoteDisconnect
  #
  #     identified_by :current_user, :current_user_device
  #
  #     def connect
  #       self.current_user = find_user
  #       self.current_user_device = [current_user, request.headers["Device-Id"]]
  #     end
  #   end
  #
  #   # Disconnect only the user's specific device
  #   RageCable::Connection.disconnect(current_user_device: [user, "device-123"])
  #
  # @param identified_by [Hash] a single key-value pair where the key is a declared identifier
  # @raise [ArgumentError] if no identifier, multiple identifiers, or an unknown identifier is provided
  # @!method self.disconnect(**identified_by)
end

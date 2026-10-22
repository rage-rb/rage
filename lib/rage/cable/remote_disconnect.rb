# frozen_string_literal: true

# Include this module in your connection class to enable server-initiated disconnections.
#
# This allows you to disconnect WebSocket connections from anywhere in your application
# using {Rage::Cable::Connection.disconnect Rage::Cable::Connection.disconnect}. A common
# use case is forcing a logout when a user's session is invalidated or their account is suspended.
#
# @example
#   class RageCable::Connection < Rage::Cable::Connection
#     include Rage::Cable::RemoteDisconnect
#
#     identified_by :current_user
#
#     def connect
#       self.current_user = find_verified_user
#     end
#   end
#
#   # Later, elsewhere in your application:
#   RageCable::Connection.disconnect(current_user: user)
#
module Rage::Cable::RemoteDisconnect
  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    # Disconnect all connections matching the specified identifier.
    # @example Disconnect all connections for a user
    #   RageCable::Connection.disconnect(current_user: User.find(1))
    def disconnect(protocol_options: nil, **identified_by)
      raise ArgumentError, "An identifier must be provided" if identified_by.empty?
      raise ArgumentError, "Only one identifier can be provided" if identified_by.size > 1

      id_pair = identified_by.first
      unless __identifiers&.include?(id_pair[0])
        raise ArgumentError, "Unknown identifier: #{id_pair[0]}"
      end

      message = if protocol_options
        raise ArgumentError, "protocol_options must be a Hash" unless protocol_options.is_a?(Hash)
        protocol_options.to_json
      else
        ""
      end

      Rage::PubSub.publish(message, topic: ["rage", name, id_pair])
    end
  end

  private

  def __remote_disconnect_setup(connection, protocol)
    __identified_by_map.each do |identified_by|
      Rage::PubSub.subscribe(topic: ["rage", self.class.name, identified_by], subscription_id: connection) do |message|
        protocol_options = JSON.parse(message, symbolize_names: true) unless message.empty?
        protocol.on_remote_disconnect(connection, protocol_options)
        connection.close
      end
    end
  end

  def __remote_disconnect_cleanup(connection)
    __identified_by_map&.each do |identified_by|
      Rage::PubSub.unsubscribe(topic: ["rage", self.class.name, identified_by], subscription_id: connection)
    end
  end
end

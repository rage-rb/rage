# frozen_string_literal: true

class Rage::Cable::Router
  # @private
  def initialize
    # Hash<String(channel name) => Proc(new channel instance)>
    @channels_map = {}
    init_connection_class
  end

  # Calls the `connect` method on the `Connection` class to handle authentication.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @return [true] if the connection was accepted
  # @return [false] if the connection was rejected
  def process_connection(connection)
    env = connection.env

    cable_connection = @connection_class.new(env)
    Rage::Telemetry.tracer.span_cable_connection_process(connection: cable_connection, action: :connect, env:) do
      cable_connection.connect
    end

    if cable_connection.rejected?
      Rage.logger.debug { "An unauthorized connection attempt was rejected" }
    else
      env["rage.identified_by"] = cable_connection.__identified_by_map
      env["rage.cable"] = {}
    end

    !cable_connection.rejected?
  end

  # Calls the `subscribed` method on the specified channel.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param identifier [String] the identifier of the subscription
  # @param channel_name [String] the name of the channel class
  # @param params [Hash] the params hash associated with the subscription
  #
  # @return [:invalid] if the subscription class does not exist
  # @return [:rejected] if the subscription was rejected
  # @return [:subscribed] if the subscription was accepted
  def process_subscription(connection, identifier, channel_name, params)
    channel_class = @channels_map[channel_name] || begin
      begin
        klass = Object.const_get(channel_name)
      rescue NameError
        nil
      end

      if klass.nil? || !klass.ancestors.include?(Rage::Cable::Channel)
        Rage.logger.debug { "Subscription class not found: #{channel_name}" }
        return :invalid
      end

      klass.__register_actions.tap do |available_actions|
        Rage.logger.debug { "Compiled #{channel_name}. Available remote actions: #{available_actions}." }
      end

      @channels_map[channel_name] = klass
    end

    channel = channel_class.new(connection, params, connection.env["rage.identified_by"])
    channel.__run_action(:subscribed)

    if channel.subscription_rejected?
      Rage.logger.debug { "#{channel_name} is transmitting the subscription rejection" }
      # if the subscription is rejected in the `subscribed` method, ActionCable will additionally run
      # the `unsubscribed` method; this makes little sense to me as the client was never subscribed in
      # the first place; additionally, I don't think this behaviour is documented anywhere;
      # so, I'm going to leave this line commented out for now;
      # channel.__run_action(:unsubscribed)
      :rejected
    else
      Rage.logger.debug { "#{channel_name} is transmitting the subscription confirmation" }
      connection.env["rage.cable"][identifier] = channel
      :subscribed
    end
  end

  # Calls the handler method on the specified channel.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  # @param identifier [String] the identifier of the subscription
  # @param action_name [Symbol] the name of the handler method
  # @param data [Object] the data sent by the client
  #
  # @return [:no_subscription] if the client is not subscribed to the specified channel
  # @return [:unknown_action] if the action does not exist on the specified channel
  # @return [:processed] if the message has been successfully processed
  def process_message(connection, identifier, action_name, data)
    channel = connection.env["rage.cable"][identifier]
    unless channel
      Rage.logger.debug { "Unable to find the subscription" }
      return :no_subscription
    end

    if channel.__has_action?(action_name)
      channel.__run_action(action_name, data)
      :processed
    else
      Rage.logger.debug { "Unable to process #{channel.class.name}##{action_name}" }
      :unknown_action
    end
  end

  # Runs the `unsubscribed` methods on all the channels the client is subscribed to.
  #
  # @param connection [Rage::Cable::WebSocketConnection] the connection object
  def process_disconnection(connection)
    env = connection.env

    env["rage.cable"]&.each do |_, channel|
      channel.__run_action(:unsubscribed)
    end

    cable_connection = @connection_class.new(env, env["rage.identified_by"])

    Rage::Telemetry.tracer.span_cable_connection_process(connection: cable_connection, action: :disconnect, env:) do
      cable_connection.disconnect
    end
  end

  # @private
  def reset
    @channels_map.clear
    init_connection_class
  end

  private

  def init_connection_class
    @connection_class = if Object.const_defined?("RageCable::Connection")
      RageCable::Connection
    elsif Object.const_defined?("ApplicationCable::Connection")
      ApplicationCable::Connection
    else
      puts "WARNING: Could not find the RageCable connection class! All connections will be accepted by default."
      Rage::Cable::Connection
    end
  end
end

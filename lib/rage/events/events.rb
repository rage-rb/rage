# frozen_string_literal: true

module Rage::Events
  # Publish an event.
  # @param event [Object] the event to publish
  # @example
  #   # define an event
  #   UserRegistered = Data.define(:user_id)
  #   # publish the event
  #   Rage::Events.publish(UserRegistered.new(user_id: 1))
  def self.publish(event)
    handler = __event_handlers[event.class] || __build_event_handler(event.class)
    handler.call(event)

    nil
  end

  # @private
  def self.__registered_subscribers
    @__registered_subscribers ||= Hash.new { |hash, key| hash[key] = [] }
  end

  # @private
  def self.__register_subscriber(event_class, handler_class)
    __registered_subscribers[event_class] << handler_class
  end

  # @private
  def self.__get_subscribers(event_class)
    event_class.ancestors.take_while { |klass|
      klass != Object && klass != Data
    }.each_with_object([]) { |klass, memo|
      memo.concat(__registered_subscribers[klass]).uniq! if __registered_subscribers.has_key?(klass)
    }
  end

  # @private
  def self.__event_handlers
    @__event_handlers ||= {}
  end

  # @private
  def self.__build_event_handler(event_class)
    subscriber_calls = __get_subscribers(event_class).map { |subscriber_class|
      if subscriber_class.__is_deferred
        "#{subscriber_class}.enqueue(event)"
      else
        "#{subscriber_class}.new.__handle(event)"
      end
    }.join("; ")

    if subscriber_calls.empty?
      ->(_) {}
    else
      __event_handlers[event_class] = eval("->(event) { #{subscriber_calls} }")
    end
  end

  # @private
  def self.__reset_subscribers
    __registered_subscribers.clear
    __event_handlers.clear

    Rage::Events.__eager_load_subscribers
  end

  # @private
  def self.__eager_load_subscribers
    subscribers = Dir["#{Rage.root}/app/**/*.rb"].select do |path|
      File.foreach(path).any? do |line|
        line.include?("include Rage::Events::Subscriber") || line.include?("subscribe_to")
      end
    end

    subscribers.each do |path|
      Rage.code_loader.load_file(path)
    end

  rescue => e
    puts "ERROR: Failed to load an event subscriber: #{e.class} (#{e.message})."
    puts e.backtrace.join("\n")
  end
end

require_relative "subscriber"

if Rage.env.development?
  if Iodine.running?
    Rage::Events.__eager_load_subscribers
  else
    Iodine.on_state(:on_start) { Rage::Events.__eager_load_subscribers }
  end
end

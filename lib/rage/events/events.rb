# frozen_string_literal: true

module Rage::Events
  # Publish an event.
  # @param event [Object] the event to publish
  # @return [Boolean] whether the event has been published, i.e. whether there are any subscribers
  # @example
  #   # define an event
  #   UserRegistered = Data.define(:user_id)
  #   # publish the event
  #   Rage::Events.publish(UserRegistered.new(user_id: 1))
  def self.publish(event)
    subscribers = __get_subscribers(event.class)
    return false if subscribers.empty?

    subscribers.each do |subscriber|
      if subscriber.__is_deferred
        subscriber.enqueue(event)
      else
        subscriber.new.__handle(event)
      end
    end

    true
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
  def self.__event_subscribers
    @__event_subscribers ||= {}
  end

  # @private
  def self.__get_subscribers(event_class)
    __event_subscribers[event_class] || begin
      subscribers = event_class.ancestors.take_while { |klass|
        klass != Object && klass != Data
      }.each_with_object([]) { |klass, memo|
        memo.concat(__registered_subscribers[klass]).uniq! if __registered_subscribers.has_key?(klass)
      }

      if subscribers.any?
        __event_subscribers[event_class] = subscribers
      else
        []
      end
    end
  end

  # @private
  def self.__reset_subscribers
    __registered_subscribers.clear
    __event_subscribers.clear

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

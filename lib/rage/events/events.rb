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
    subscribers = __get_subscribers(event)
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

  # Publish multiple events sequentially.
  # Use this method when the successful handling of one event should trigger the publication of the next.
  # @param events [Array<Object>] the events to publish
  # @example
  #   Rage::Events.publish_ordered(OrderCreated.new, DiscountApplied.new)
  def self.publish_ordered(*events)
    if events.none? { |event| __has_deferred_subscribers?(event) }
      events.each { |event| publish(event) }
    else
      events.each do |event|
        subscribers = __get_subscribers(event)
        subscribers.each { |subscriber| GroupTask.enqueue(event, subscriber) }
      end
    end

    nil
  end

  # A shorthand for building a subscriber module.
  # @example
  #   include Rage::Events::Subscriber(MyEvent)
  # @example
  #   include Rage::Events::Subscriber[MyEvent]
  def self.Subscriber(*)
    Rage::Events::Subscriber.new(*)
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
  def self.__get_subscribers(event)
    __event_subscribers[event.class] || begin
      subscribers = event.class.ancestors.take_while { |klass|
        klass != Object && klass != Data
      }.each_with_object([]) { |klass, memo|
        memo.concat(__registered_subscribers[klass]).uniq! if __registered_subscribers.has_key?(klass)
      }

      if subscribers.any?
        __event_subscribers[event.class] = subscribers
      else
        []
      end
    end
  end

  # @private
  def self.__has_deferred_subscribers?(event)
    cache_key = [event.class, :has_deferred_subscribers]

    if __event_subscribers.has_key?(cache_key)
      __event_subscribers[cache_key]
    else
      __event_subscribers[cache_key] = __get_subscribers(event).any?(&:__is_deferred)
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
      File.foreach(path).any? { |line| line.include?("include Rage::Events::Subscriber") }
    end

    subscribers.each do |path|
      Rage.code_loader.load_file(path)
    end

  rescue => e
    puts "ERROR: Failed to load an event subscriber: #{e.class} (#{e.message})."
    puts e.backtrace.join("\n")
  end

  autoload :GroupTask, "rage/events/group_task"
  autoload :GroupScheduler, "rage/events/group_scheduler"
end

require_relative "subscriber"

if Rage.env.development?
  if Iodine.running?
    Rage::Events.__eager_load_subscribers
  else
    Iodine.on_state(:on_start) { Rage::Events.__eager_load_subscribers }
  end
end

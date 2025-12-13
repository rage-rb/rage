# frozen_string_literal: true

##
# `Rage::Events` provides a lightweight event-driven system for publishing and subscribing to events.
# Define events as data structures, register subscriber classes, and publish events to notify all relevant subscribers.
# Subscribers can process events and optionally receive additional context with each event.
#
# Define an event:
# ```ruby
# UserRegistered = Data.define(:user_id)
# ```
#
# Define a subscriber:
# ```ruby
# class SendWelcomeEmail
#   include Rage::Events::Subscriber
#   subscribe_to UserRegistered
#
#   def call(event)
#     puts "Sending welcome email to user #{event.user_id}"
#   end
# end
# ```
#
# Publish an event:
# ```ruby
# Rage::Events.publish(UserRegistered.new(user_id: 1))
# ```
#
module Rage::Events
  # Publish an event to all subscribers registered for the event's class or its ancestors.
  # Optionally, additional context data can be provided and passed to each subscriber.
  #
  # @param event [Object] the event to publish
  # @param context [Object] additional data to publish along with the event
  # @example Publish an event
  #   Rage::Events.publish(MyEvent.new)
  # @example Publish an event with context
  #   Rage::Events.publish(MyEvent.new, context: { published_at: Time.now })
  def self.publish(event, context: nil)
    handler = __event_handlers[event.class] || __build_event_handler(event.class)
    handler.call(event, context)

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
    subscriber_calls = __get_subscribers(event_class).map do |subscriber_class|
      arguments = "event"

      context_type, _ = subscriber_class.instance_method(:call).parameters.find do |param_type, param_name|
        param_name == :context || param_type == :keyrest
      end

      if context_type
        if context_type == :keyreq
          arguments += ", context: context || {}"
        else
          arguments += ", context:"
        end
      end

      if subscriber_class.__is_deferred
        "#{subscriber_class}.enqueue(#{arguments})"
      else
        "#{subscriber_class}.new.__call(#{arguments})"
      end
    end

    if subscriber_calls.empty?
      ->(_, _) {}
    else
      __event_handlers[event_class] = eval <<-RUBY
        ->(event, context) { #{subscriber_calls.join("; ")} }
      RUBY
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
  if Rage.config.internal.initialized?
    Rage::Events.__eager_load_subscribers
  else
    Rage.config.after_initialize { Rage::Events.__eager_load_subscribers }
  end
end

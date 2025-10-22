# frozen_string_literal: true

module Rage::Events
  # Publish an event.
  # @param event [Object] the event to publish
  # @param metadata [Object] the metadata to publish along with the event
  # @example
  #   # define an event
  #   UserRegistered = Data.define(:user_id)
  #
  #   # publish the event
  #   Rage::Events.publish(UserRegistered.new(user_id: 1))
  #
  #   # publish with metadata
  #   Rage::Events.publish(UserRegistered.new(user_id: 1), metadata: { published_at: Time.now })
  def self.publish(event, metadata: nil)
    handler = __event_handlers[event.class] || __build_event_handler(event.class)
    handler.call(event, metadata)

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

      metadata_type, _ = subscriber_class.instance_method(:handle).parameters.find do |param_type, param_name|
        param_name == :metadata || param_type == :keyrest
      end

      if metadata_type
        if metadata_type == :keyreq
          arguments += ", metadata: metadata || {}"
        else
          arguments += ", metadata:"
        end
      end

      if subscriber_class.__is_deferred
        "#{subscriber_class}.enqueue(#{arguments})"
      else
        "#{subscriber_class}.new.__handle(#{arguments})"
      end
    end

    if subscriber_calls.empty?
      ->(_, _) {}
    else
      __event_handlers[event_class] = eval <<-RUBY
        ->(event, metadata) { #{subscriber_calls.join("; ")} }
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

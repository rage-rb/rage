# frozen_string_literal: true

##
# Include this module in a class to make it an event subscriber.
#
# Example:
#
# ```ruby
# # Define an event class
# MyEvent = Data.define
#
# # Define the subscriber class
# class MySubscriber
#   include Rage::Events::Subscriber[MyEvent]
#
#   def handle(event)
#     puts "Handled event: #{event.inspect}"
#   end
# end
#
# # Publish an event
# Rage::Events.publish(MyEvent.new)
# ```
#
# When an event matching the specified class is published, the `handle` method will be invoked with the event instance.
#
# You can also subscribe to multiple event classes:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber[EventA, EventB]
#
#   def handle(event)
#     puts "Handled event: #{event.inspect}"
#   end
# end
# ```
#
# Subscribers are executed synchronously by default. You can make a subscriber asynchronous by calling `deferred_subscriber`:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber[MyEvent]
#   deferred_subscriber
#
#   def handle(event)
#     puts "Handled event in background: #{event.inspect}"
#   end
# end
# ```
#
# Such subscriber will be executed in the background using Rage's deferred task system.
#
class Rage::Events::Subscriber < Module
  def self.[](*)
    new(*)
  end

  attr_accessor :__event_classes, :__is_deferred

  def initialize(*event_classes)
    super()
    @__event_classes = event_classes
    @__is_deferred = false

    define_singleton_method(:inspect) do
      events = event_classes.join(", ")
      "#<#{self.class}[#{events}]>"
    end
  end

  def ==(other)
    other.is_a?(self.class) &&
      @__event_classes == other.__event_classes &&
      !!@__is_deferred == !!other.__is_deferred
  end

  def included(handler_class)
    handler_class.include Impl
    handler_class.extend ClassMethods

    handler_class.__event_classes = @__event_classes
    handler_class.__is_deferred = @__is_deferred

    @__event_classes.each do |event_class|
      Rage::Events.__register_subscriber(event_class, handler_class)
    end

    unless handler_class.method_defined?(:handle)
      handler_class.define_method(:handle) { |_| }
    end
  end

  module Impl
    def __handle(_)
      Rage.logger.with_context(subscriber: self.class.name) do
        handle(_)
        true
      rescue Exception => e
        Rage.logger.error("Subscriber failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        raise Rage::Deferred::TaskFailed if self.class.__is_deferred
        false
      end
    end
  end

  module ClassMethods
    attr_accessor :__event_classes, :__is_deferred

    def deferred_subscriber(enabled = true)
      @__is_deferred = !!enabled

      if @__is_deferred
        include Rage::Deferred::Task
        alias_method :perform, :__handle
      end
    end
  end
end

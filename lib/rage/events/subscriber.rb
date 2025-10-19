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
#   include Rage::Events::Subscriber
#   subscribe_to MyEvent
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
#   include Rage::Events::Subscriber
#   subscribe_to EventA, EventB
#
#   def handle(event)
#     puts "Received event: #{event.inspect}"
#   end
# end
# ```
#
# Subscribers are executed synchronously by default. You can make a subscriber asynchronous by passing the `deferred` option:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber
#   subscribe_to MyEvent, deferred: true
#
#   def handle(event)
#     puts "Received event in background: #{event.inspect}"
#   end
# end
# ```
#
# Such subscriber will be executed in the background using Rage's deferred task system.
#
module Rage::Events::Subscriber
  def self.included(handler_class)
    handler_class.include InstanceMethods
    handler_class.extend ClassMethods
  end

  module InstanceMethods
    def handle(_)
    end

    def __handle(event, metadata = nil)
      Rage.logger.with_context(self.class.__log_context) do
        metadata.nil? ? handle(event) : handle(event, metadata: metadata.freeze)
        true
      rescue Exception => e
        Rage.logger.error("Subscriber failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        raise Rage::Deferred::TaskFailed if self.class.__is_deferred
        false
      end
    end
  end

  module ClassMethods
    attr_reader :__event_classes, :__is_deferred, :__log_context

    def subscribe_to(*event_classes, deferred: false)
      @__event_classes = event_classes
      @__is_deferred = !!deferred
      @__log_context = { subscriber: name }.freeze

      @__event_classes.each do |event_class|
        Rage::Events.__register_subscriber(event_class, self)
      end

      if @__is_deferred
        include Rage::Deferred::Task
        alias_method :perform, :__handle
      end
    end
  end
end

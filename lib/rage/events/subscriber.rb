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
    handler_class.extend ClassMethods
  end

  def handle(_)
  end

  def __handle(event, metadata: nil)
    Rage.logger.with_context(self.class.__log_context) do
      metadata.nil? ? handle(event) : handle(event, metadata: metadata.freeze)
      true
    rescue Exception => _e
      e = self.class.__rescue_handlers ? __run_rescue_handlers(_e) : _e

      if e
        Rage.logger.error("Subscriber failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        raise Rage::Deferred::TaskFailed if self.class.__is_deferred
      end
    end
  end

  module ClassMethods
    attr_accessor :__event_classes, :__is_deferred, :__log_context, :__rescue_handlers

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

    def rescue_from(*klasses, with: nil, &block)
      unless with
        if block_given?
          with = Rage::Internal.define_dynamic_method(self, block)
        else
          raise ArgumentError, "No handler provided. Pass the `with` keyword argument or provide a block."
        end
      end

      if @__rescue_handlers.nil?
        @__rescue_handlers = []
      elsif @__rescue_handlers.frozen?
        @__rescue_handlers = @__rescue_handlers.dup
      end

      @__rescue_handlers.unshift([klasses, with])
    end

    # @private
    def inherited(klass)
      klass.__rescue_handlers = @__rescue_handlers.freeze
      klass.subscribe_to(*@__event_classes, deferred: @__is_deferred) if @__event_classes
    end

    def __register_rescue_handlers
      return if method_defined?(:__run_rescue_handlers, false) || @__rescue_handlers.nil?

      matcher_calls = @__rescue_handlers.map do |klasses, handler|
        handler_call = instance_method(handler).arity == 0 ? handler : "#{handler}(exception)"
        "when #{klasses.join(", ")} then #{handler_call}"
      end

      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __run_rescue_handlers(exception)
          case exception
          #{matcher_calls.join("\n")}
          end

          nil
        rescue Exception => e
          e
        end
      RUBY
    end
  end
end

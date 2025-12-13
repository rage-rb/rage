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
#   def call(event)
#     puts "Received event: #{event.inspect}"
#   end
# end
#
# # Publish an event
# Rage::Events.publish(MyEvent.new)
# ```
#
# When an event matching the specified class is published, the `call` method will be invoked with the event instance.
#
# You can also subscribe to multiple event classes:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber
#   subscribe_to EventA, EventB
#
#   def call(event)
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
#   def call(event)
#     puts "Received event in background: #{event.inspect}"
#   end
# end
# ```
#
# Such subscriber will be executed in the background using Rage's deferred task system.
#
# You can also define custom error handling for exceptions raised during event processing using `rescue_from`:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber
#   subscribe_to MyEvent
#
#   rescue_from StandardError do |exception|
#     puts "An error occurred: #{exception.message}"
#   end
# end
# ```
#
# @see ClassMethods
#
module Rage::Events::Subscriber
  def self.included(handler_class)
    handler_class.extend ClassMethods
  end

  # @private
  def call(_)
  end

  # @private
  def __call(event, context: nil)
    Rage.logger.with_context(self.class.__log_context) do
      with_exception_handler do
        context.nil? ? call(event) : call(event, context: context.freeze)
      end
    rescue Exception => e
      Rage.logger.error("Subscriber failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      raise e if self.class.__is_deferred
    end
  end

  private

  def __deferred_suppress_exception_logging?
    true
  end

  def with_exception_handler
    yield
  end

  module ClassMethods
    # @private
    attr_accessor :__event_classes, :__is_deferred, :__log_context, :__rescue_handlers

    # Subscribe the class to one or more events.
    #
    # @param event_classes [Class, Array<Class>] one or more event classes to subscribe to
    # @param deferred [Boolean] whether to process events asynchronously
    def subscribe_to(*event_classes, deferred: false)
      @__event_classes = (@__event_classes || []) | event_classes
      @__is_deferred = !!deferred
      @__log_context = { subscriber: name }.freeze

      @__event_classes.each do |event_class|
        Rage::Events.__register_subscriber(event_class, self)
      end

      if @__is_deferred
        include Rage::Deferred::Task
        alias_method :perform, :__call
      end
    end

    # Define exception handlers for the subscriber.
    #
    # @param klasses [Class, Array<Class>] one or more exception classes to handle
    # @param with [Symbol, String] the method name to call when an exception is raised
    # @yield [exception] optional block to handle the exception
    # @note If you do not re-raise exceptions in deferred subscribers, the subscriber will be marked as successful and Rage will not attempt to retry it.
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

      rebuild_exception_handler!
    end

    # @private
    def inherited(klass)
      klass.__rescue_handlers = @__rescue_handlers.freeze
      klass.subscribe_to(*@__event_classes, deferred: @__is_deferred) if @__event_classes
    end

    private

    def rebuild_exception_handler!
      rescue_calls = @__rescue_handlers.map do |klasses, handler|
        <<~RUBY
          rescue #{klasses.join(", ")} => e
            method(:#{handler}).arity == 0 ? #{handler} : #{handler}(e)
        RUBY
      end

      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        private def with_exception_handler
          yield
          #{rescue_calls.join("\n")}
        end
      RUBY
    end
  end
end

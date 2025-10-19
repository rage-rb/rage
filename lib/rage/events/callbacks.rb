##
# `Rage::Events::Callbacks` provides a DSL for defining before-publish callbacks
# in event classes. These callbacks are executed before an event is published,
# allowing you to publish additional metadata along with the event.
#
# To use this module, include it in your event class and define one or more `before_publish` callbacks:
#
# ```ruby
# MyEvent = Data.define do
#   include Rage::Events::Callbacks
#
#   before_publish do
#     { current_user_id: Current.user.id }
#   end
# end
# ```
#
# The data returned by the `before_publish` block will be available to subscribers under the `metadata` keyword argument:
#
# ```ruby
# class MySubscriber
#   include Rage::Events::Subscriber
#   subscribe_to MyEvent
#
#   def handle(event, metadata:)
#     puts "Event published by user: #{metadata[:current_user_id]}"
#   end
# end
# ```
#
# `before_publish` callbacks do not have to return anything, and can be used to implement things like centralized logging:
#
# ```ruby
# MyEvent = Data.define do
#   include Rage::Events::Callbacks
#
#   before_publish do |event|
#     Rage.logger.with_context(event: event.to_h) do
#       Rage.logger.info("published event")
#     end
#   end
# end
# ```
#
module Rage::Events::Callbacks
  def self.included(klass)
    klass.include(InstanceMethods)
    klass.extend(ClassMethods)
  end

  module InstanceMethods
    def __run_before_publish_callbacks
      callbacks = self.class.__before_callbacks

      if callbacks.length == 1
        result = callbacks[0].call(self)
        result.is_a?(Hash) ? result : {}
      else
        meta, i = {}, 0

        while i < callbacks.length
          result = callbacks[i].call(self)
          meta.merge!(result) if result.is_a?(Hash)
          i += 1
        end

        meta
      end
    end
  end

  module ClassMethods
    attr_reader :__before_callbacks

    def before_publish(&block)
      (@__before_callbacks ||= []) << block
    end

    def __has_before_callbacks?
      @__before_callbacks&.any?
    end
  end
end

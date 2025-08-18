# frozen_string_literal: true

##
# `Rage::Deferred::Task` is a module that should be included in classes that represent tasks to be executed
# in the background by the `Rage::Deferred` queue. It ensures the tasks can be retried in case of a failure,
# with a maximum number of attempts and an exponential backoff strategy.
#
# To define a task, include the module and implement the `#perform` method:
#
# ```ruby
# class ProcessImage
#   include Rage::Deferred::Task
#
#   def initialize(image_path:)
#     @image_path = image_path
#   end
#
#   def perform
#     # logic to process the image
#   end
# end
# ```
#
# The `#perform` method should contain the logic for the task. It does not accept any arguments, as the task instance itself carries all necessary data.
#
module Rage::Deferred::Task
  MAX_ATTEMPTS = 5
  private_constant :MAX_ATTEMPTS

  BACKOFF_INTERVAL = 5
  private_constant :BACKOFF_INTERVAL

  def perform
  end

  # @private
  def __with_log_tag(tag)
    if tag
      Rage.logger.tagged(tag) { yield }
    else
      yield
    end
  end

  # @private
  def __perform(metadata)
    args = Rage::Deferred::Metadata.get_args(metadata)
    attempts = Rage::Deferred::Metadata.get_attempts(metadata)
    request_id = Rage::Deferred::Metadata.get_request_id(metadata)

    context = { task: self.class.name }
    context[:attempt] = attempts + 1 if attempts

    Rage.logger.with_context(context) do
      __with_log_tag(request_id) do
        perform(*args)
        true
      rescue Exception => e
        Rage.logger.error("Deferred task failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        false
      end
    end
  end

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def perform_async(*args, delay: nil, delay_until: nil)
      Rage::Deferred.__queue.enqueue(
        Rage::Deferred::Metadata.build(self, args),
        delay:,
        delay_until:
      )
    end

    # @private
    def __should_retry?(attempts)
      attempts < MAX_ATTEMPTS
    end

    # @private
    def __next_retry_in(attempts)
      rand(BACKOFF_INTERVAL * 2**attempts.to_i) + 1
    end
  end
end

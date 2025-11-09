# frozen_string_literal: true

##
# `Rage::Deferred` is an in-process background task queue with at-least-once delivery guarantee that allows you to schedule tasks to be executed later.
# It can be used to offload long-running operations, such as sending emails or communicating with external APIs.
#
# To schedule a task, first define a task class that includes `Rage::Deferred::Task` and implements the `#perform` method.
#
# ```ruby
# class SendWelcomeEmail
#   include Rage::Deferred::Task
#
#   def perform(email)
#     # logic to send the welcome email
#   end
# end
# ```
#
# Then, push the task to the deferred queue:
#
# ```ruby
# SendWelcomeEmail.enqueue(email: user.email)
# ```
#
# You can also specify a delay for the task execution using the `delay` option:
#
# ```ruby
# SendWelcomeEmail.enqueue(email: user.email, delay: 10) # execute after 10 seconds
# ```
#
# Or you can specify a specific time in the future when the task should be executed:
#
# ```ruby
# SendWelcomeEmail.enqueue(email: user.email, delay_until: Time.now + 3600) # execute in 1 hour
# ```
#
module Rage::Deferred
  # Push an instance to the deferred queue without including the `Rage::Deferred::Task` module.
  # @param instance [Object] the instance to wrap
  # @param delay [Integer, nil] the delay in seconds before the task is executed
  # @param delay_until [Time, nil] the specific time when the task should be executed
  # @example Schedule an arbitrary method to be called in the background
  #   class SendWelcomeEmail < Struct.new(:email)
  #     def call
  #     end
  #   end
  #
  #   email_service = SendWelcomeEmail.new(email: user.email)
  #   Rage::Deferred.wrap(email_service).call
  def self.wrap(instance, delay: nil, delay_until: nil)
    Rage::Deferred::Proxy.new(instance, delay:, delay_until:)
  end

  # @private
  def self.__backend
    @__backend ||= Rage.config.deferred.backend
  end

  # @private
  def self.__queue
    @__queue ||= Rage::Deferred::Queue.new(__backend)
  end

  # @private
  def self.__load_tasks
    current_time = Time.now.to_i

    __backend.pending_tasks.each do |task_id, task_wrapper, publish_at|
      publish_in = publish_at - current_time if publish_at
      __queue.schedule(task_id, task_wrapper, publish_in:)
    rescue => e
      puts "ERROR: Failed to load deferred task #{task_id}: #{e.class} (#{e.message}). Removing task from the queue."
      __backend.remove(task_id)
    end
  end

  module Backends
  end

  class PushTimeout < StandardError
  end

  # @private
  class TaskFailed < StandardError
  end
end

require_relative "task"
require_relative "queue"
require_relative "proxy"
require_relative "context"
require_relative "backends/disk"
require_relative "backends/nil"

if Iodine.running?
  Rage::Deferred.__load_tasks
else
  Iodine.on_state(:on_start) { Rage::Deferred.__load_tasks }
end

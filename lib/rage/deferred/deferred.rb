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
# SendWelcomeEmail.perform_async(email: user.email)
# ```
#
# You can also specify a delay for the task execution using the `delay` option:
#
# ```ruby
# SendWelcomeEmail.perform_async(email: user.email, delay: 10) # execute after 10 seconds
# ```
#
# Or you can specify a specific time in the future when the task should be executed:
#
# ```ruby
# SendWelcomeEmail.perform_async(email: user.email, delay_until: Time.now + 3600) # execute in 1 hour
# ```
#
module Rage::Deferred
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
    end
  end

  module Backends
  end

  class PushTimeout < StandardError
  end
end

require_relative "task"
require_relative "queue"
require_relative "metadata"
require_relative "backends/disk"
require_relative "backends/nil"

if Iodine.running?
  Rage::Deferred.__load_tasks
else
  Iodine.on_state(:on_start) { Rage::Deferred.__load_tasks }
end

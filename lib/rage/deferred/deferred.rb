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
#    def initialize(email:)
#      @email = email
#    end
#
#   def perform
#     # logic to send the welcome email
#   end
# end
# ```
#
# Then, push the task to the deferred queue:
#
# ```ruby
# Rage.deferred << SendWelcomeEmail.new(email: user.email)
# ```
#
# As you can see, the `perform` method does not accept any arguments. Instead, each task object represents a specific peace of work to be done, and you can pass any necessary data to the task when you create it.
#
# You can also specify a delay for the task execution when using the `push` method:
#
# ```ruby
# Rage.deferred.push(SendWelcomeEmail.new(email: user.email), delay: 10) # execute after 10 seconds
# ```
#
# Or you can specify a specific time in the future when the task should be executed:
# ```ruby
# Rage.deferred.push(SendWelcomeEmail.new(email: user.email), delay_until: Time.now + 3600) # execute in 1 hour
# ```
#
module Rage::Deferred
  # Send a task to the deferred queue.
  # @param task [Rage::Deferred::Task] the task to execute
  # @param delay [Integer] execute the task after the specified number of seconds
  # @param delay_until [Time] execute the task at the specific time in the future
  def self.push(task, delay: nil, delay_until: nil)
    unless task.is_a?(Rage::Deferred::Task)
      raise ArgumentError, "#{task.class} is not an instance of `Rage::Deferred::Task`"
    end

    __queue.enqueue(task, delay:, delay_until:)

    self
  end

  class << self
    alias_method :<<, :push
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
    end
  end

  module Backends
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

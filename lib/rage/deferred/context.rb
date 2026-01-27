# frozen_string_literal: true

##
# Context for deferred tasks.
# The class encapsulates the context associated with a deferred task, and allows to store it without modifying the task instance.
#
# @private
class Rage::Deferred::Context
  def self.build(task, args, kwargs)
    logger = Thread.current[:rage_logger]

    [
      task,
      args.empty? ? nil : args,
      kwargs.empty? ? nil : kwargs,
      nil,
      logger&.dig(:tags),
      logger&.dig(:context),
      nil
    ]
  end

  # @return [Class] the task class
  def self.get_task(context)
    context[0]
  end

  # @return [Array, nil] arguments the task was enqueued with
  def self.get_args(context)
    context[1]
  end

  # @return [Array] arguments the task was enqueued with, creating it if it does not exist
  def self.get_or_create_args(context)
    context[1] ||= []
  end

  # @return [Hash, nil] keyword arguments the task was enqueued with
  def self.get_kwargs(context)
    context[2]
  end

  # @return [Hash] keyword arguments the task was enqueued with, creating it if it does not exist
  def self.get_or_create_kwargs(context)
    context[2] ||= {}
  end

  # @return [Integer, nil] number of attempts made to process the task
  def self.get_attempts(context)
    context[3]
  end

  # Increments the number of attempts made to process the task
  def self.inc_attempts(context)
    context[3] = context[3].to_i + 1
  end

  # @return [Array, nil] log tags associated with the task
  def self.get_log_tags(context)
    context[4]
  end

  # @return [Hash, nil] log context associated with the task
  def self.get_log_context(context)
    context[5]
  end

  # @return [Hash, nil] user context associated with the task
  def self.get_user_context(context)
    context[6]
  end

  # @return [Hash] user context associated with the task, creating it if it does not exist
  def self.get_or_create_user_context(context)
    context[6] ||= {}
  end
end

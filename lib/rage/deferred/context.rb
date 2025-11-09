# frozen_string_literal: true

##
# Context for deferred tasks.
# The class encapsulates the context associated with a deferred task, and allows to store it without modifying the task instance.
#
class Rage::Deferred::Context
  def self.build(task, args, kwargs, storage: nil)
    request_id = Thread.current[:rage_logger][:tags][0] if Thread.current[:rage_logger]

    [
      task,
      args.empty? ? nil : args,
      kwargs.empty? ? nil : kwargs,
      nil,
      request_id
    ]
  end

  def self.get_task(context)
    context[0]
  end

  def self.get_args(context)
    context[1]
  end

  def self.get_kwargs(context)
    context[2]
  end

  def self.get_attempts(context)
    context[3]
  end

  def self.inc_attempts(context)
    context[3] = context[3].to_i + 1
  end

  def self.get_request_id(context)
    context[4]
  end
end

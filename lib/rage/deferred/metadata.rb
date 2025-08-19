# frozen_string_literal: true

class Rage::Deferred::Metadata
  def self.build(task, args, kwargs)
    request_id = Thread.current[:rage_logger][:tags][0] if Thread.current[:rage_logger]

    [
      task,
      args.empty? ? nil : args,
      kwargs.empty? ? nil : kwargs,
      nil,
      request_id
    ]
  end

  def self.get_task(metadata)
    metadata[0]
  end

  def self.get_args(metadata)
    metadata[1]
  end

  def self.get_kwargs(metadata)
    metadata[2]
  end

  def self.get_attempts(metadata)
    metadata[3]
  end

  def self.get_request_id(metadata)
    metadata[4]
  end

  def self.inc_attempts(metadata)
    metadata[3] = metadata[3].to_i + 1
  end
end

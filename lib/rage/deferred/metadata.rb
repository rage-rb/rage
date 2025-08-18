# # frozen_string_literal: true

class Rage::Deferred::Metadata
  def self.build(task, args)
    request_id = Thread.current[:rage_logger][:tags][0] if Thread.current[:rage_logger]

    [task, args, nil, request_id]
  end

  def self.get_task(metadata)
    metadata[0]
  end

  def self.get_args(metadata)
    metadata[1]
  end

  def self.get_attempts(metadata)
    metadata[2]
  end

  def self.get_request_id(metadata)
    metadata[3]
  end

  def self.inc_attempts(metadata)
    metadata[2] = metadata[2].to_i + 1
  end
end

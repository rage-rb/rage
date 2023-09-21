# frozen_string_literal: true

require "resolv"

class Rage::FiberScheduler
  def io_wait(io, events, timeout = nil)
    f = Fiber.current
    ::Iodine::Scheduler.attach(io.fileno, events, timeout&.ceil || 0) { f.resume }
    Fiber.yield

    events
  end

  # TODO: this is more synchronous than asynchronous right now
  def io_read(io, buffer, length, offset = 0)
    loop do
      string = ::Iodine::Scheduler.read(io.fileno, length, offset)

      if string.nil?
        return offset
      end

      if string.empty?
        io_wait(io, IO::READABLE)
        next
      end

      buffer.set_string(string, offset)
      offset += string.bytesize

      size = string.bytesize
      break if size >= length
      length -= size
    end

    offset
  end

  def io_write(io, buffer, length, offset = 0)
    bytes_to_write = length
    bytes_to_write = buffer.size if length == 0

    ::Iodine::Scheduler.write(io.fileno, buffer.get_string, bytes_to_write, offset)

    buffer.size - offset
  end

  def kernel_sleep(duration = nil)
    if duration
      f = Fiber.current
      ::Iodine.run_after((duration * 1000).to_i) { f.resume } 
      Fiber.yield
    end
  end

  # TODO: GC works a little strange with this closure;
  # 
  # def timeout_after(duration, exception_class = Timeout::Error, *exception_arguments, &block)
  #   fiber, block_status = Fiber.current, :running
  #   ::Iodine.run_after((duration * 1000).to_i) do
  #     fiber.raise(exception_class, exception_arguments) if block_status == :running
  #   end

  #   result = block.call
  #   block_status = :finished

  #   result
  # end

  def address_resolve(hostname)
    Resolv.getaddresses(hostname)
  end

  def block(blocker, timeout = nil)
    f = Fiber.current
    ::Iodine.subscribe("unblock:#{f.object_id}") do
      ::Iodine.defer { ::Iodine.unsubscribe("unblock:#{f.object_id}") }
      f.resume
    end
    # TODO support timeout
    Fiber.yield
  end

  def unblock(_blocker, fiber)
    ::Iodine.publish("unblock:#{fiber.object_id}", "")
  end

  def fiber(&block)
    fiber = Fiber.new(blocking: false) do
      Fiber.current.__set_result(block.call)
    end
    fiber.resume

    fiber
  end

  def close
    ::Iodine::Scheduler.close
  end
end

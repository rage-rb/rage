# frozen_string_literal: true

require "resolv"

class Rage::FiberScheduler
  MAX_READ = 65536
  TIMEOUT_WORKER_INTERVAL = 100 # miliseconds

  def initialize
    @root_fiber = Fiber.current
    @dns_cache = {}

    @fiber_timeouts = Hash.new { |h, k| h[k] = {} }

    start_timeout_worker
  end

  def io_wait(io, events, timeout = nil)
    f = Fiber.current
    ::Iodine::Scheduler.attach(io.fileno, events, timeout&.ceil) { |err| f.resume(err) }

    err = Fiber.defer(io.fileno)
    if err == false || (err && err < 0)
      err
    else
      events
    end
  end

  def io_read(io, buffer, length, offset = 0)
    length_to_read = if length == 0
      buffer.size > MAX_READ ? MAX_READ : buffer.size
    else
      length
    end

    while true
      string = ::Iodine::Scheduler.read(io.fileno, length_to_read, offset)

      if string.nil?
        return offset
      end

      if string.empty?
        return -Errno::EAGAIN::Errno
      end

      buffer.set_string(string, offset)

      size = string.bytesize
      offset += size
      return offset if size < length_to_read || size >= buffer.size

      Fiber.pause
    end
  end

  unless ENV["RAGE_DISABLE_IO_WRITE"]
    def io_write(io, buffer, length, offset = 0)
      bytes_to_write = length
      bytes_to_write = buffer.size if length == 0

      ::Iodine::Scheduler.write(io.fileno, buffer.get_string, bytes_to_write, offset)

      bytes_to_write - offset
    end
  end

  def kernel_sleep(duration = nil)
    block(nil, duration || 0)
    Fiber.pause if duration.nil? || duration < 1
  end

  def timeout_after(duration, exception_class = Timeout::Error, *exception_arguments, &block)
    fiber = Fiber.current
    timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

    @fiber_timeouts[fiber][timeout] = {
      exception_class: exception_class,
      exception_arguments: exception_arguments
    }

    begin
      block.call
    ensure
      @fiber_timeouts[fiber].delete(timeout)
      @fiber_timeouts.delete(fiber) if @fiber_timeouts[fiber].empty?
    end
  end

  def address_resolve(hostname)
    @dns_cache[hostname] ||= begin
      ::Iodine.run_after(60_000) do
        @dns_cache[hostname] = nil
      end

      Resolv.getaddresses(hostname)
    end
  end

  def block(_blocker, timeout = nil)
    f, fulfilled, channel = Fiber.current, false, Fiber.current.__block_channel(true)

    resume_fiber_block = proc do
      unless fulfilled
        fulfilled = true
        ::Iodine.defer { ::Iodine.unsubscribe(channel) }
        f.resume
      end
    end

    ::Iodine.subscribe(channel, &resume_fiber_block)
    if timeout
      ::Iodine.run_after((timeout * 1000).to_i, &resume_fiber_block)
    end

    Fiber.yield
  end

  def unblock(_blocker, fiber)
    ::Iodine.publish(fiber.__block_channel, "", Iodine::PubSub::PROCESS)
  end

  def fiber(&block)
    parent = Fiber.current

    fiber = if parent == @root_fiber
      # the fiber to wrap a request in
      Fiber.new(blocking: false) do
        Fiber.current.__set_id
        Fiber.current.__set_result(block.call)
      end
    else
      # the fiber was created in the user code
      logger = Thread.current[:rage_logger]

      Fiber.new(blocking: false) do
        Thread.current[:rage_logger] = logger
        Fiber.current.__set_result(block.call)
        # send a message for `Fiber.await` to work
        Iodine.publish("await:#{parent.object_id}", "", Iodine::PubSub::PROCESS) if parent.alive?
      rescue Exception => e
        Fiber.current.__set_err(e)
        Iodine.publish("await:#{parent.object_id}", Fiber::AWAIT_ERROR_MESSAGE, Iodine::PubSub::PROCESS) if parent.alive?
      end
    end

    fiber.resume

    fiber
  end

  def close
    ::Iodine::Scheduler.close
  end

  private

  def start_timeout_worker
    ::Iodine.run_every(Rage::FiberScheduler::TIMEOUT_WORKER_INTERVAL) do
      check_timeouts
    end
  end

  def check_timeouts
    @fiber_timeouts.each_pair do |fiber, timeouts|
      timeouts.delete_if do |timeout, context|
        next false if Process.clock_gettime(Process::CLOCK_MONOTONIC) < timeout

        fiber.raise(context[:exception_class], *context[:exception_arguments]) if fiber.alive?

        true
      end
    end
  end
end

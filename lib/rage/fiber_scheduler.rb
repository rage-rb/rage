# frozen_string_literal: true

require "resolv"

class Rage::FiberScheduler
  MAX_READ = 65536

  def initialize
    @root_fiber = Fiber.current
    @dns_cache = {}

    @fiber_timeouts = Hash.new { |h, k| h[k] = {} }
  end

  def io_wait(io, events, timeout = nil)
    f = Fiber.current
    ::Iodine::Scheduler.attach(io.fileno, events, timeout&.ceil) { |err| f.resume(err) if f.alive? }

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
    f = Fiber.current
    timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

    @fiber_timeouts[f][timeout] = {
      exception_class: exception_class,
      exception_arguments: exception_arguments
    }

    schedule_timeout_check

    begin
      block.call
    ensure
      @fiber_timeouts[f].delete(timeout)
      @fiber_timeouts.delete(f) if @fiber_timeouts[f].empty?
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
        f.resume if f.alive?
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
        Rage::Telemetry.tracer.span_core_fiber_dispatch do
          Fiber.current.__set_result(block.call)
        end
      end
    else
      # the fiber was created in the user code
      Fiber.new(blocking: false) do
        Rage::Telemetry.tracer.span_core_fiber_spawn(parent:) do
          Fiber.current.__set_result(block.call)
        end
        # send a message for `Fiber.await` to work
        Iodine.publish(parent.__await_channel, "", Iodine::PubSub::PROCESS) if parent.alive?
      rescue Exception => e
        Fiber.current.__set_err(e)
        Iodine.publish(parent.__await_channel, Fiber::AWAIT_ERROR_MESSAGE, Iodine::PubSub::PROCESS) if parent.alive?
      end
    end

    fiber.resume

    fiber
  end

  def close
    ::Iodine::Scheduler.close
  end

  private

  def schedule_timeout_check
    return if @fiber_timeouts.empty?

    closest_timeout = nil
    @fiber_timeouts.each_value do |timeouts|
      timeouts.each_key do |timeout|
        closest_timeout = timeout if closest_timeout.nil? || timeout < closest_timeout
      end
    end

    return unless closest_timeout

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    delay_ms = ((closest_timeout - now) * 1000).ceil
    delay_ms = 0 if delay_ms < 0

    ::Iodine.run_after(delay_ms) do
      check_timeouts
      schedule_timeout_check
    end
  end

  def check_timeouts
    fibers_to_raise = []

    @fiber_timeouts.each do |fiber, timeouts|
      timeouts.each do |timeout, context|
        next false if Process.clock_gettime(Process::CLOCK_MONOTONIC) < timeout

        fibers_to_raise << -> do
          fiber.raise(context[:exception_class], *context[:exception_arguments])

          Iodine.unsubscribe(fiber.__block_channel)
          Iodine.unsubscribe(fiber.__await_channel)
        end
      end
    end

    fibers_to_raise.each(&:call)

    fibers_to_raise.clear
  end
end

# frozen_string_literal: true

require "resolv"

class Rage::FiberScheduler
  MAX_READ = 65536

  # Initialize the scheduler, storing the root fiber and an empty DNS cache.
  def initialize
    @root_fiber = Fiber.current
    @dns_cache = {}
  end

  # Wait for I/O events on a file descriptor, yielding the fiber until ready or timeout.
  def io_wait(io, events, timeout = nil)
    f = Fiber.current
    gen = (f.__wait_generation += 1)

    ::Iodine::Scheduler.attach(io.fileno, events, timeout&.ceil) do |err|
      f.resume(err) if f.alive? && gen == f.__wait_generation
    end

    err = Fiber.defer(io.fileno)
    if err == false || (err && err < 0)
      err
    else
      events
    end
  end

  # Read data from an I/O object into a buffer, pausing the fiber between reads.
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
    # Write data from a buffer to an I/O object.
    def io_write(io, buffer, length, offset = 0)
      bytes_to_write = length
      bytes_to_write = buffer.size if length == 0

      ::Iodine::Scheduler.write(io.fileno, buffer.get_string, bytes_to_write, offset)

      bytes_to_write - offset
    end
  end

  # Pause the current fiber for the specified duration.
  def kernel_sleep(duration = nil)
    block(nil, duration || 0)
    Fiber.pause if duration.nil? || duration < 1
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

  # Resolve a hostname to IP addresses, caching results for 60 seconds.
  def address_resolve(hostname)
    @dns_cache[hostname] ||= begin
      ::Iodine.run_after(60_000) do
        @dns_cache[hostname] = nil
      end

      Resolv.getaddresses(hostname)
    end
  end

  # Block the current fiber until unblocked or timeout.
  def block(_blocker, timeout = nil)
    f, fulfilled = Fiber.current, false

    gen = (f.__wait_generation += 1)
    channel = f.__block_channel = "block:#{f.object_id}:#{gen}"

    resume_fiber_block = proc do
      unless fulfilled
        fulfilled = true
        ::Iodine.defer { ::Iodine.unsubscribe(channel) }
        f.resume if f.alive? && gen == f.__wait_generation
      end
    end

    ::Iodine.subscribe(channel, &resume_fiber_block)
    if timeout
      ::Iodine.run_after((timeout * 1000).to_i, &resume_fiber_block)
    end

    Fiber.yield
  end

  # Unblock a fiber by publishing to its block channel.
  def unblock(_blocker, fiber)
    ::Iodine.publish(fiber.__block_channel, "", Iodine::PubSub::PROCESS) if fiber.__block_channel
  end

  # Interrupt a fiber by incrementing its generation and raising an exception.
  def fiber_interrupt(fiber, exception)
    fiber.__wait_generation += 1
    fiber.raise(exception)
  end

  if ENV["RAGE_ENABLE_WORKER_POOL"] && defined?(Iodine::WorkerPool)
    Iodine.on_state(:pre_start) { puts "INFO: Using Worker Pool" }

    # Offload a blocking operation to a worker pool, yielding until complete.
    def blocking_operation_wait(work)
      f = Fiber.current
      gen = (f.__wait_generation += 1)

      worker_pool.enqueue(work) do
        f.resume if f.alive? && gen == f.__wait_generation
      end

      Fiber.yield
    end

    private def worker_pool
      @worker_pool ||= Iodine::WorkerPool.new(1)
    end
  end

  # Create and schedule a new non-blocking fiber, handling request and user-spawned fibers differently.
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
        Iodine.publish(parent.__await_channel, "", Iodine::PubSub::PROCESS) if parent.__await_channel
      rescue Exception => e
        Fiber.current.__set_err(e)
        Iodine.publish(parent.__await_channel, Fiber::AWAIT_ERROR_MESSAGE, Iodine::PubSub::PROCESS) if parent.__await_channel
      end
    end

    fiber.__wait_generation = 0
    fiber.resume

    fiber
  end

  # Clean up by closing the worker pool and Iodine scheduler.
  def close
    @worker_pool&.close
    ::Iodine::Scheduler.close
  end
end

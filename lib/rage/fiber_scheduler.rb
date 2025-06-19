# frozen_string_literal: true

require "resolv"

class Rage::FiberScheduler
  MAX_READ = 65536
  TIMEOUT_WORKER_INTERVAL = 100 # miliseconds

  def initialize
    @root_fiber = Fiber.current
    @dns_cache = {}

    @alive_fibers = {}
    @timeout_mutex = Mutex.new

    start_timeout_worker
  end

  def io_wait(io, events, timeout = nil)
    f = Fiber.current
    ::Iodine::Scheduler.attach(io.fileno, events, timeout&.ceil) { |err| f.resume(err) }

    timeout_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    @alive_fibers[f.__get_id] = {
      fiber: f,
      timeout_deadline: timeout_deadline,
      exception_class: RageTimeout,
    }

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
  def timeout_after(duration, exception_class = Timeout::Error, *exception_arguments, &block)
    fiber = Fiber.current
    timeout_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

    p "duration #{duration}"
    p "fiber id #{fiber.__get_id}"

    @timeout_mutex.synchronize do
      @alive_fibers[fiber.__get_id] = {
        fiber: fiber,
        timeout_deadline: timeout_deadline,
        exception_class: exception_class,
        exception_arguments: exception_arguments,
      }
    end

    begin
      block.call
    ensure
      @timeout_mutex.synchronize do
        @alive_fibers.delete(fiber.__get_id)
      end
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

  def start_timeout_worker
    return unless ::Iodine.running?

    ::Iodine.run_every(Rage::FiberScheduler::TIMEOUT_WORKER_INTERVAL) do
      @timeout_mutex.synchronize do
        check_timeouts
      end
    end
  end

  def check_timeouts
    p @alive_fibers.count

    @alive_fibers.delete_if do |_, fiber_hash|
      current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      p current_time
      p "deadline #{fiber_hash[:timeout_deadline]}"
      p "fiber id #{fiber_hash[:fiber].__get_id}"

      return false if current_time < fiber_hash[:timeout_deadline]

      p 'after'

      fiber = fiber_hash[:fiber]
      # unblock(nil, fiber)

      # if fiber.alive?
        fiber.raise(RageTimeout)
      # else
        # fiber.kill
      # end

      true
    end
  end
end

class RageTimeout < StandardError; end
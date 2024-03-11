# frozen_string_literal: true

class Fiber
  # @private
  AWAIT_ERROR_MESSAGE = "err"

  # @private
  def __set_result(result)
    @__result = result
  end

  # @private
  def __get_result
    @__result
  end

  # @private
  def __set_err(err)
    @__err = err
  end

  # @private
  def __get_err
    @__err
  end

  # @private
  def __set_id
    @__rage_id = object_id.to_s
  end

   # @private
  def __get_id
    @__rage_id
  end

  # @private
  def __block_channel(force = false)
    @__block_channel_i ||= 0
    @__block_channel_i += 1 if force

    "block:#{object_id}:#{@__block_channel_i}"
  end

  # @private
  # pause a fiber and resume in the next iteration of the event loop
  def self.pause
    f = Fiber.current
    Iodine.defer { f.resume }
    Fiber.yield
  end

  # @private
  # under normal circumstances, the method is a copy of `yield`, but it can be overriden to perform
  # additional steps on yielding, e.g. releasing AR connections; see "lib/rage/rails.rb"
  class << self
    alias_method :defer, :yield
  end

  # Wait on several fibers at the same time. Calling this method will automatically pause the current fiber, allowing the
  #   server to process other requests. Once all fibers have completed, the current fiber will be automatically resumed.
  #
  # @param fibers [Fiber, Array<Fiber>] one or several fibers to wait on. The fibers must be created using the `Fiber.schedule` call.
  # @example
  #   Fiber.await([
  #     Fiber.schedule { request_1 },
  #     Fiber.schedule { request_2 },
  #   ])
  # @note This method should only be used when multiple fibers have to be processed in parallel. There's no need to use `Fiber.await` for single IO calls.
  def self.await(fibers)
    f, fibers = Fiber.current, Array(fibers)

    # check which fibers are alive (i.e. have yielded) and which have errored out
    i, err, num_wait_for = 0, nil, 0
    while i < fibers.length
      if fibers[i].alive?
        num_wait_for += 1
      else
        err = fibers[i].__get_err
        break if err
      end
      i += 1
    end

    # raise if one of the fibers has errored out or return the result if none have yielded
    if err
      raise err
    elsif num_wait_for == 0
      return fibers.map!(&:__get_result)
    end

    # wait on async fibers; resume right away if one of the fibers errors out
    Iodine.subscribe("await:#{f.object_id}") do |_, err|
      if err == AWAIT_ERROR_MESSAGE
        f.resume
      else
        num_wait_for -= 1
        f.resume if num_wait_for == 0
      end
    end

    Fiber.yield
    Iodine.defer { Iodine.unsubscribe("await:#{f.object_id}") }

    # if num_wait_for is not 0 means we exited prematurely because of an error
    if num_wait_for > 0
      raise fibers.find(&:__get_err).__get_err
    else
      fibers.map!(&:__get_result)
    end
  end
end

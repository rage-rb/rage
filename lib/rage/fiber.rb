class Fiber
  # @private
  def __set_result(result)
    @__result = result
  end

  # @private
  def __get_result
    @__result
  end

  # @private
  # pause a fiber and resume in the next iteration of the event loop
  def self.pause
    f = Fiber.current
    Iodine.defer { f.resume }
    Fiber.yield
  end

  # Wait on several fibers at the same time. Calling this method will automatically pause the current fiber, allowing the
  #   server to process other requests. Once all fibers have completed, the current fiber will be automatically resumed.
  #
  # @param fibers [Fiber, Array<Fiber>] one or several fibers to wait on. The fibers must be created using the `Fiber.schedule` call.
  # @example
  #   Fiber.await(
  #     Fiber.schedule { request_1 },
  #     Fiber.schedule { request_2 },
  #   )
  # @note This method should only be used when multiple fibers have to be processed in parallel. There's no need to use `Fiber.await` for single IO calls.
  def self.await(*fibers)
    f = Fiber.current

    num_wait_for = fibers.count(&:alive?)
    return fibers.map(&:__get_result) if num_wait_for == 0

    Iodine.subscribe("await:#{f.object_id}") do
      num_wait_for -= 1
      f.resume if num_wait_for == 0
    end

    Fiber.yield
    Iodine.defer { Iodine.unsubscribe("await:#{f.object_id}") }

    fibers.map(&:__get_result)
  end
end

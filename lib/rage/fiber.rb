class Fiber
  def __set_result(result)
    @__result = result
  end

  def __get_result
    @__result
  end

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

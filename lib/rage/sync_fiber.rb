# mock fiber methods as RSpec tests don't run concurrently
class Fiber
  def self.schedule(&block)
    fiber = Fiber.new(blocking: true) do
      Fiber.current.__set_id
      Fiber.current.__set_result(block.call)
    end
    fiber.resume

    fiber
  end

  def self.await(fibers)
    Array(fibers).map(&:__get_result)
  end
end

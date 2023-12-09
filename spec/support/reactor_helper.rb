module ReactorHelper
  ##
  # we need Iodine reactor up and running to test the scheduler, but once the reactor is started, it will block until
  # stopped, running only the code that is scheduled to run inside it; hence, we first schedule the test to run and
  # then set up a periodic task to stop the reactor; only after that the reactor is started;
  # the block is expected to return a proc to enable the code inside the reactor to communicate the test result to rspec.
  #
  def within_reactor(&block)
    fiber = nil

    Iodine.defer { fiber = Fiber.schedule { Fiber.current.__set_result(block.call) } }
    Iodine.run_every(200) { Iodine.stop unless fiber.alive? rescue Iodine.stop }
    Iodine.run_after(10_000) { fiber.raise("execution expired") }

    Iodine.threads = Iodine.workers = 1
    Iodine.start

    expectation = fiber.__get_result
    expectation.call
  end
end

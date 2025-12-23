# frozen_string_literal: true

##
# Rage provides a simple and efficient API to wait on several instances of IO at the same time - {Fiber.await}.
#
# Let's say we have the following controller:
# ```ruby
# class UsersController < RageController::API
#   def show
#     user = Net::HTTP.get(URI("http://users.service/users/#{params[:id]}"))
#     bookings = Net::HTTP.get(URI("http://bookings.service/bookings?user_id=#{params[:id]}"))
#     render json: { user: user, bookings: bookings }
#   end
# end
# ```
# This code will fire two consecutive HTTP requests. If each request takes 1 second to execute, the total execution time will be 2 seconds.<br>
# With {Fiber.await}, we can significantly decrease the overall execution time by changing the code to fire the requests concurrently.
#
# To do this, we will need to:
#
# 1. Wrap every request in a separate fiber using {Fiber.schedule};
# 2. Pass newly created fibers into {Fiber.await};
#
# ```ruby
# class UsersController < RageController::API
#   def show
#     user, bookings = Fiber.await([
#       Fiber.schedule { Net::HTTP.get(URI("http://users.service/users/#{params[:id]}")) },
#       Fiber.schedule { Net::HTTP.get(URI("http://bookings.service/bookings?user_id=#{params[:id]}")) }
#     ])
#
#     render json: { user: user, bookings: bookings }
#   end
# end
# ```
# With this change, if each request takes 1 second to execute, the total execution time will still be 1 second.
#
# ## Creating fibers
# Many developers see fibers as "lightweight threads" that should be used in conjunction with fiber pools, the same way we use thread pools for threads.<br>
# Instead, it makes sense to think of fibers as regular Ruby objects. We don't use a pool of arrays when we need to create an array - we create a new object and let Ruby and the GC do their job.<br>
# Same applies to fibers. Feel free to create as many fibers as you need on demand.
#
# ## Active Record Connections
#
# Let's consider the following controller, where we update a record in the database:
#
# ```ruby
# class UsersController < RageController::API
#   def update
#     User.update!(params[:id], email: params[:email])
#     render status: :ok
#   end
# end
# ```
#
# The `User.update!` call here checks out an Active Record connection, and Rage will automatically check it back in once the action is completed. So far so good!
#
# Let's consider another example:
#
# ```ruby
# require "net/http"
#
# class UsersController < RageController::API
#   def update
#     User.update!(params[:id], email: params[:email]) # takes 5ms
#     Net::HTTP.post_form(URI("https://mailing.service/update"), { user_id: params[:id] }) # takes 50ms
#     render status: :ok
#   end
# end
# ```
#
# Here, we've added another step: once the record is updated, we will send a request to update the user's data in the mailing list service.
#
# However, in this case, we want to release the Active Record connection before the action is completed. You can see that we need the connection only for the `User.update!` call.
# The next 50ms the code will spend waiting for the HTTP request to finish, and if we don't release the Active Record connection right away, other fibers won't be able to use it.
#
# Active Record 7.2 handles this case by using [#with_connection](https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/ConnectionPool.html#method-i-with_connection) internally.
# With older Active Record versions, Rage handles this case on its own by keeping track of blocking calls and releasing Active Record connections between them.
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
  def __await_channel(force = false)
    @__fiber_channel_i ||= 0
    @__fiber_channel_i += 1 if force

    "await:#{object_id}:#{@__fiber_channel_i}"
  end

  # @private
  attr_accessor :__awaited_fileno

  # @private
  # pause a fiber and resume in the next iteration of the event loop
  def self.pause
    f = Fiber.current
    Iodine.defer { f.resume }
    Fiber.yield
  end

  # @private
  # under normal circumstances, the method is a copy of `yield`, but it can be overriden to perform
  # additional steps on yielding, e.g. releasing AR connections; see "lib/rage/ext/setup.rb"
  class << self
    alias_method :defer, :yield
  end

  # Wait on several fibers at the same time. Calling this method will automatically pause the current fiber, allowing the
  # server to process other requests. Once all fibers have completed, the current fiber will be automatically resumed.
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
    await_channel = f.__await_channel(true)

    Rage::Telemetry.tracer.span_core_fiber_await(fibers:) do
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
      Iodine.subscribe(await_channel) do |_, err|
        if err == AWAIT_ERROR_MESSAGE
          f.resume
        else
          num_wait_for -= 1
          f.resume if num_wait_for == 0
        end
      end

      Fiber.defer(-1)
      Iodine.defer { Iodine.unsubscribe(await_channel) }

      # if num_wait_for is not 0 means we exited prematurely because of an error
      if num_wait_for > 0
        raise fibers.find(&:__get_err).__get_err
      else
        fibers.map!(&:__get_result)
      end
    end
  end

  # @!method self.schedule(&block)
  #   Create a non-blocking fiber. Should mostly be used in conjunction with `Fiber.await`.
  #   @example
  #     Fiber.await([
  #       Fiber.schedule { request_1 },
  #       Fiber.schedule { request_2 }
  #     ])
  #   @example
  #     fiber_1 = Fiber.schedule { request_1 }
  #     fiber_2 = Fiber.schedule { request_2 }
  #     Fiber.await([fiber_1, fiber_2])
end

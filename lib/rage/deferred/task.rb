# frozen_string_literal: true

##
# `Rage::Deferred::Task` is a module that should be included in classes that represent tasks to be executed
# in the background by the `Rage::Deferred` queue. It ensures the tasks can be retried in case of a failure,
# with a maximum number of attempts and an exponential backoff strategy.
#
# To define a task, include the module and implement the `#perform` method:
#
# ```ruby
# class ProcessImage
#   include Rage::Deferred::Task
#
#   def initialize(image_path:)
#     @image_path = image_path
#   end
#
#   def perform
#     # logic to process the image
#   end
# end
# ```
#
# The `#perform` method should contain the logic for the task. It does not accept any arguments, as the task instance itself carries all necessary data.
#
module Rage::Deferred::Task
  MAX_ATTEMPTS = 5
  private_constant :MAX_ATTEMPTS

  BACKOFF_INTERVAL = 5
  private_constant :BACKOFF_INTERVAL

  def perform
  end

  # @private
  def __should_retry?(attempts)
    attempts.to_i < MAX_ATTEMPTS
  end

  # @private
  def __next_retry_in(attempts)
    rand(BACKOFF_INTERVAL * 2**attempts.to_i) + 1
  end
end

# frozen_string_literal: true

##
# The class implements a deferred task that is used to publish events in order.
# One task is used to execute one subscriber for a specific event.
#
class Rage::Events::GroupTask
  include Rage::Deferred::Task

  def perform(event, subscriber)
    group_scheduler = Rage::Events::GroupScheduler.instance(meta.request_id)

    group_scheduler.enter(group: event, resource: subscriber)

    is_completed = subscriber.new.__handle(event)
    raise Rage::Deferred::TaskFailed unless is_completed

    group_scheduler.exit(group: event, resource: subscriber)
  rescue => e
    group_scheduler.exit(group: event, resource: subscriber) unless meta.will_retry?
    raise e
  end
end

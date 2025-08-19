# frozen_string_literal: true

class Rage::Deferred::Proxy
  class Wrapper
    include Rage::Deferred::Task

    def perform(instance, method_name, *, **)
      instance.public_send(method_name, *, **)
    end
  end

  def initialize(instance, delay: nil, delay_until: nil)
    @instance = instance

    @delay = delay
    @delay_until = delay_until
  end

  def method_missing(method_name, *, **)
    self.class.define_method(method_name) do |*args, **kwargs|
      Wrapper.enqueue(@instance, method_name, *args, delay: @delay, delay_until: @delay_until, **kwargs)
    end

    send(method_name, *, **)
  end

  def respond_to_missing?(_, _)
    true
  end
end

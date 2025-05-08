# frozen_string_literal: true

module Hooks
  def initialize_hooks
    @hooks = Hash.new { |h, k| h[k] = [] }
  end

  def push_hook(callback, hook_family)
    @hooks[hook_family] << callback if callback
  end

  def run_hooks_for!(hook_family, base = nil)
    @hooks[hook_family].each do |callback|
      if base
        base.instance_exec(&callback)
      else
        callback.call
      end
    end
  end
end

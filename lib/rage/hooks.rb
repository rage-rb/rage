# frozen_string_literal: true

module Hooks
  def self.included(base)
    base.class_eval do
      def self.new(*args, &block)
        base_instance = super
        base_instance.initialize_hooks
        base_instance
      end
    end
  end

  def initialize_hooks
    @hooks = Hash.new { |h, k| h[k] = [] }
  end

  def push_hook(callback, hook_family)
    @hooks[hook_family] << callback if callback.is_a?(Proc)
  end

  def run_hooks_for!(hook_family, context = nil)
    @hooks[hook_family].each do |callback|
      if context
        context.instance_exec(&callback)
      else
        callback.call
      end
    end

    true
  end
end

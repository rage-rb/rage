# frozen_string_literal: true

class Rage::Configuration
  class Hooks
    def initialize
      @after_initialize = []
    end
    def push_hook(callback, hook_family)
      case hook_family
      when :after_initialize
        @after_initialize.push(callback)
      else
        Rage.logger.error("Unknown hook family: #{hook_family}. Callback has not been registered")
      end
    end

    def run(hook_family)
      case hook_family
      when :after_initialize
        @after_initialize.each { |callback| callback.call }
      else
        Rage.logger.error("Unknown hook family: #{hook_family}. Callbacks have not been run")
      end
    end
  end
end

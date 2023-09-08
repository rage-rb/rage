# frozen_string_literal: true

class RageController::API
  class << self
    def __register_action(action)
      raise "The action '#{action}' could not be found for #{self}" unless method_defined?(action)

      class_eval <<-RUBY
        def __run_#{action}
          #{action}

          [@status, @headers, @body]
        end
      RUBY
    end
  end # class << self

  def initialize(env, params)
    @env = env
    @params = params
    @status, @headers, @body = 204, {}, []
    @rendered = false
  end

  def render(json: nil, plain: nil, status: nil)
    if @rendered
      raise "Render was called multiple times in this action. Render doesn't terminate execution of the action, so if you want to exit an action after rendering, you need to do something like 'render(...) and return'"
    end
    @rendered = true

    if json || plain
      @body << if json
        json.is_a?(String) ? json : json.to_json
      else
        plain
      end

      @status = 200
    end

    if status
      @status = if status.is_a?(Symbol)
        Rack::Utils::SYMBOL_TO_STATUS_CODE(status)
      else
        status
      end
    end
  end

  def head(status)
    @status = if status.is_a?(Symbol)
      Rack::Utils::SYMBOL_TO_STATUS_CODE(status)
    else
      status
    end
  end
end

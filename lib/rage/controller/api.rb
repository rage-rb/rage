# frozen_string_literal: true

class RageController::API
  class << self
    def __register_action(action)
      raise "The action '#{action}' could not be found for #{self}" unless method_defined?(action)

      before_actions_chunk = if @before_actions
        filtered_before_actions = @before_actions.select do |h|
          (h[:only].nil? || h[:only].include?(action)) &&
            (h[:except].nil? || !h[:except].include?(action))
        end

        lines = filtered_before_actions.map do |h|
          <<-RUBY
            #{h[:name]}
            return [@status, @headers, @body] if @rendered
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      class_eval <<-RUBY
        def __run_#{action}
          #{before_actions_chunk}
          #{action}

          [@status, @headers, @body]
        end
      RUBY
    end

    # Register a new `before_action` hook.
    #
    # @param action_name [String] the name of the callback to add
    # @param only [Symbol, Array<Symbol>] restrict the callback to run only for specific actions
    # @param except [Symbol, Array<Symbol>] restrict the callback to run for all actions except specified
    # @example
    #   before_action :find_photo, only: :show
    #   def find_photo
    #     ...
    #   end
    def before_action(action_name, only: nil, except: nil)
      (@before_actions ||= []) << {
        name: action_name,
        only: only && Array(only),
        except: except && Array(except)
      }
    end
  end # class << self

  def initialize(env, params)
    @env = env
    @params = params
    @status, @headers, @body = 204, {}, []
    @rendered = false
  end

  # Send a response to the client.
  #
  # @param json [String, Object] send a json response to the client; objects like arrays will be serialized automatically
  # @param plain [String] send a text response to the client
  # @param status [Integer, Symbol] set a response status
  # @example
  #   render json: { hello: "world" }
  # @example
  #   render status: :ok
  # @example
  #   render plain: "hello world", status: 201
  # @note `render` doesn't terminate execution of the action, so if you want to exit an action after rendering, you need to do something like 'render(...) and return'
  def render(json: nil, plain: nil, status: nil)
    raise "Render was called multiple times in this action" if @rendered
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
        ::Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
      else
        status
      end
    end
  end

  # Send a response with no body.
  #
  # @param status [Integer, Symbol] set a response status
  # @example
  #   head :unauthorized
  # @example
  #   head 429
  def head(status)
    @rendered = true

    @status = if status.is_a?(Symbol)
      ::Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
    else
      status
    end
  end
end

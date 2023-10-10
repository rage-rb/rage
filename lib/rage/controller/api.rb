# frozen_string_literal: true

class RageController::API
  class << self
    # @private
    # used by the router to register a new action;
    # registering means defining a new method which calls the action, makes additional calls (e.g. before actions) and
    # sends a correct response down to the server;
    # returns the name of the newly defined method;
    def __register_action(action)
      raise "The action '#{action}' could not be found for #{self}" unless method_defined?(action)

      before_actions_chunk = if @__before_actions
        filtered_before_actions = @__before_actions.select do |h|
          (!h[:only] || h[:only].include?(action)) &&
            (!h[:except] || !h[:except].include?(action))
        end

        lines = filtered_before_actions.map do |h|
          condition = if h[:if] && h[:unless]
            "if #{h[:if]} && !#{h[:unless]}"
          elsif h[:if]
            "if #{h[:if]}"
          elsif h[:unless]
            "unless #{h[:unless]}"
          end

          <<-RUBY
            #{h[:name]} #{condition}
            return [@__status, @__headers, @__body] if @__rendered
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      rescue_handlers_chunk = if @__rescue_handlers
        lines = @__rescue_handlers.map do |klasses, handler|
          <<-RUBY
          rescue #{klasses.join(", ")} => __e
            #{handler}(__e)
            [@__status, @__headers, @__body]
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

          [@__status, @__headers, @__body]

          #{rescue_handlers_chunk}
        end
      RUBY
    end

    # @private
    attr_writer :__before_actions, :__rescue_handlers

    # @private
    # pass the variable down to the child; the child will continue to use it until changes need to be made;
    # only then the object will be copied; the frozen state communicates that the object is shared with the parent;
    def inherited(klass)
      klass.__before_actions = @__before_actions.freeze
      klass.__rescue_handlers = @__rescue_handlers.freeze
    end

    # @private
    @@__tmp_name_seed = ("a".."i").to_a.permutation

    # @private
    # define temporary method based on a block
    def define_tmp_method(block)
      name = @@__tmp_name_seed.next.join
      define_method("__rage_tmp_#{name}", block)
    end

    ############
    #
    # PUBLIC API
    #
    ############

    # Register a global exception handler. Handlers are inherited and matched from bottom to top.
    #
    # @param klasses [Class, Array<Class>] exception classes to watch on
    # @param with [Symbol] the name of a handler method. The method must take one argument, which is the raised exception. Alternatively, you can pass a block, which must also take one argument.
    # @example
    #   rescue_from User::NotAuthorized, with: :deny_access
    #
    #   def deny_access(exception)
    #     head :forbidden
    #   end
    # @example
    #   rescue_from User::NotAuthorized do |_|
    #     head :forbidden
    #   end
    # @note Unlike Rails, the handler must always take an argument. Use `_` if you don't care about the actual exception.
    def rescue_from(*klasses, with: nil, &block)
      unless with
        if block_given?
          with = define_tmp_method(block)
        else
          raise "No handler provided. Pass the `with` keyword argument or provide a block."
        end
      end

      if @__rescue_handlers.nil?
        @__rescue_handlers = []
      elsif @__rescue_handlers.frozen?
        @__rescue_handlers = @__rescue_handlers.dup
      end

      @__rescue_handlers.unshift([klasses, with])
    end

    # Register a new `before_action` hook. Calls with the same `action_name` will overwrite the previous ones.
    #
    # @param action_name [String, nil] the name of the callback to add
    # @param [Hash] opts action options
    # @option opts [Symbol, Array<Symbol>] :only restrict the callback to run only for specific actions
    # @option opts [Symbol, Array<Symbol>] :except restrict the callback to run for all actions except specified
    # @option opts [Symbol, Proc] :if only run the callback if the condition is true
    # @option opts [Symbol, Proc] :unless only run the callback if the condition is false
    # @example
    #   before_action :find_photo, only: :show
    #
    #   def find_photo
    #     Photo.first
    #   end
    # @example
    #   before_action :require_user, unless: :logged_in?
    # @example
    #   before_action :set_locale, if: -> { params[:locale] != "en-US" }
    # @example
    #   before_action do
    #     unless logged_in? # would be `controller.send(:logged_in?)` in Rails
    #       head :unauthorized
    #     end
    #   end
    # @note The block form doesn't receive an argument and is executed on the controller level as if it was a regular method.
    def before_action(action_name = nil, **opts, &block)
      if block_given?
        action_name = define_tmp_method(block)
      elsif action_name.nil?
        raise "No handler provided. Pass the `action_name` parameter or provide a block."
      end

       _only, _except, _if, _unless = opts.values_at(:only, :except, :if, :unless)

      if @__before_actions && @__before_actions.frozen?
        @__before_actions = @__before_actions.dup
      end

      action = {
        name: action_name,
        only: _only && Array(_only),
        except: _except && Array(_except),
        if: _if,
        unless: _unless
      }
      
      action[:if] = define_tmp_method(action[:if]) if action[:if].is_a?(Proc)
      action[:unless] = define_tmp_method(action[:unless]) if action[:unless].is_a?(Proc)

      if @__before_actions.nil?
        @__before_actions = [action]
      elsif i = @__before_actions.find_index { |a| a[:name] == action_name }
        @__before_actions[i] = action
      else
        @__before_actions << action
      end
    end

    # Prevent a `before_action` hook from running.
    #
    # @param action_name [String] the name of the callback to skip
    # @param only [Symbol, Array<Symbol>] restrict the callback to be skipped only for specific actions
    # @param except [Symbol, Array<Symbol>] restrict the callback to be skipped for all actions except specified
    # @example
    #   skip_before_action :find_photo, only: :create
    def skip_before_action(action_name, only: nil, except: nil)
      i = @__before_actions&.find_index { |a| a[:name] == action_name }
      raise "The following action was specified to be skipped but cannot be found: #{self}##{action_name}" unless i

      @__before_actions = @__before_actions.dup if @__before_actions.frozen?

      if only.nil? && except.nil?
        @__before_actions.delete_at(i)
        return
      end

      action = @__before_actions[i].dup
      if only
        action[:except] ? action[:except] |= Array(only) : action[:except] = Array(only)
      end
      if except
        action[:only] = Array(except)
      end

      @__before_actions[i] = action
    end
  end # class << self

  # @private
  DEFAULT_HEADERS = { "content-type" => "application/json; charset=utf-8" }.freeze

  # @private
  attr_reader :request
  def initialize(env, params)
    @__env = env
    @__params = params
    @__status, @__headers, @__body = 204, DEFAULT_HEADERS, []
    @__rendered = false
    @request = Request.new(env)
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
  # @note `render` doesn't terminate execution of the action, so if you want to exit an action after rendering, you need to do something like `render(...) and return`.
  def render(json: nil, plain: nil, status: nil)
    raise "Render was called multiple times in this action" if @__rendered
    @__rendered = true

    if json || plain
      @__body << if json
        json.is_a?(String) ? json : json.to_json
      else
        headers["content-type"] = "text/plain; charset=utf-8"
        plain.to_s
      end

      @__status = 200
    end

    if status
      @__status = if status.is_a?(Symbol)
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
    @__rendered = true

    @__status = if status.is_a?(Symbol)
      ::Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
    else
      status
    end
  end

  # Set response headers.
  #
  # @example
  #   headers["Content-Type"] = "application/pdf"
  def headers
    # copy-on-write implementation for the headers object
    @__headers = {}.merge!(@__headers) if DEFAULT_HEADERS.equal?(@__headers)
    @__headers
  end

  class Request
    # Get the request headers.
    # @example
    #  request.headers["Content-Type"] # => "application/json"
    # or request.headers["HTTP_CONTENT_TYPE"] # => "application/json"
    attr_reader :headers

    def initialize(env)
      @env = env
      @headers = extract_headers(env)
    end

    private

    def extract_headers(env)
      headers_hash = {}

      env.each do |key, value|
        if key.start_with?('HTTP_')
          original_name = key.sub('HTTP_', '').split('_').map(&:capitalize).join('-')
          headers_hash[original_name] = value
          headers_hash[key] = value
        end
      end

      headers_hash
    end
  end
end

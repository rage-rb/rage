# frozen_string_literal: true

class RageController::API
  class << self
    # @private
    # used by the router to register a new action;
    # registering means defining a new method which calls the action, makes additional calls (e.g. before actions) and
    # sends a correct response down to the server;
    # returns the name of the newly defined method;
    def __register_action(action)
      raise Rage::Errors::RouterError, "The action '#{action}' could not be found for #{self}" unless method_defined?(action)

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

          <<~RUBY
            #{h[:name]} #{condition}
            return [@__status, @__headers, @__body] if @__rendered
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      after_actions_chunk = if @__after_actions
        filtered_after_actions = @__after_actions.select do |h|
          (!h[:only] || h[:only].include?(action)) &&
            (!h[:except] || !h[:except].include?(action))
        end

        lines = filtered_after_actions.map! do |h|
          condition = if h[:if] && h[:unless]
            "if #{h[:if]} && !#{h[:unless]}"
          elsif h[:if]
            "if #{h[:if]}"
          elsif h[:unless]
            "unless #{h[:unless]}"
          end

          <<~RUBY
            #{h[:name]} #{condition}
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      rescue_handlers_chunk = if @__rescue_handlers
        lines = @__rescue_handlers.map do |klasses, handler|
          <<~RUBY
          rescue #{klasses.join(", ")} => __e
            #{handler}(__e)
            [@__status, @__headers, @__body]
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      activerecord_loaded = Rage.config.internal.rails_mode && defined?(::ActiveRecord)

      class_eval <<~RUBY,  __FILE__, __LINE__ + 1
        def __run_#{action}
          #{if activerecord_loaded
            <<~RUBY
              ActiveRecord::Base.connection_pool.enable_query_cache!
            RUBY
          end}

          #{before_actions_chunk}
          #{action}

          #{if !after_actions_chunk.empty?
            <<~RUBY
              @__rendered = true
              #{after_actions_chunk}
            RUBY
          end}

          [@__status, @__headers, @__body]

          #{rescue_handlers_chunk}

        ensure
          #{if activerecord_loaded
            <<~RUBY
              ActiveRecord::Base.connection_pool.disable_query_cache!
              if ActiveRecord::Base.connection_pool.active_connection?
                ActiveRecord::Base.connection_handler.clear_active_connections!
              end
            RUBY
          end}

          #{if method_defined?(:append_info_to_payload) || private_method_defined?(:append_info_to_payload)
            <<~RUBY
              context = {}
              append_info_to_payload(context)
              Thread.current[:rage_logger][:context] = context
            RUBY
          end}
        end
      RUBY
    end

    # @private
    attr_writer :__before_actions, :__after_actions, :__rescue_handlers

    # @private
    # pass the variable down to the child; the child will continue to use it until changes need to be made;
    # only then the object will be copied; the frozen state communicates that the object is shared with the parent;
    def inherited(klass)
      klass.__before_actions = @__before_actions.freeze
      klass.__after_actions = @__after_actions.freeze
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
    # @note Unlike in Rails, the handler must always take an argument. Use `_` if you don't care about the actual exception.
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
      action = prepare_action_params(action_name, **opts, &block)

      if @__before_actions && @__before_actions.frozen?
        @__before_actions = @__before_actions.dup
      end

      if @__before_actions.nil?
        @__before_actions = [action]
      elsif i = @__before_actions.find_index { |a| a[:name] == action_name }
        @__before_actions[i] = action
      else
        @__before_actions << action
      end
    end

    def after_action(action_name = nil, **opts, &block)
      action = prepare_action_params(action_name, **opts, &block)

      if @__after_actions && @__after_actions.frozen?
        @__after_actions = @__after_actions.dup
      end

      if @__after_actions.nil?
        @__after_actions = [action]
      elsif i = @__after_actions.find_index { |a| a[:name] == action_name }
        @__after_actions[i] = action
      else
        @__after_actions << action
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
      raise "The following action was specified to be skipped but couldn't be found: #{self}##{action_name}" unless i

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

    private

    # used by `before_action` and `after_action`
    def prepare_action_params(action_name = nil, **opts, &block)
      if block_given?
        action_name = define_tmp_method(block)
      elsif action_name.nil?
        raise "No handler provided. Pass the `action_name` parameter or provide a block."
      end

       _only, _except, _if, _unless = opts.values_at(:only, :except, :if, :unless)

      action = {
        name: action_name,
        only: _only && Array(_only),
        except: _except && Array(_except),
        if: _if,
        unless: _unless
      }

      action[:if] = define_tmp_method(action[:if]) if action[:if].is_a?(Proc)
      action[:unless] = define_tmp_method(action[:unless]) if action[:unless].is_a?(Proc)

      action
    end
  end # class << self

  # @private
  def initialize(env, params)
    @__env = env
    @__params = params
    @__status, @__headers, @__body = 204, { "content-type" => "application/json; charset=utf-8" }, []
    @__rendered = false
  end

  # Get the request object. See {Rage::Request}.
  def request
    @request ||= Rage::Request.new(@__env)
  end

  # Get the response object. See {Rage::Response}.
  def response
    @response ||= Rage::Response.new(@__headers, @__body)
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
    @__headers
  end

  # Authenticate using an HTTP Bearer token. Returns the value of the block if a token is found. Returns `nil` if no token is found.
  #
  # @yield [token] token value extracted from the `Authorization` header
  # @example
  #   user = authenticate_with_http_token do |token|
  #     User.find_by(key: token)
  #   end
  def authenticate_with_http_token
    auth_header = @__env["HTTP_AUTHORIZATION"]

    payload = if auth_header&.start_with?("Bearer")
      auth_header[7..]
    elsif auth_header&.start_with?("Token")
      auth_header[6..]
    end

    return unless payload

    token = if payload.start_with?("token=")
      payload[6..]
    else
      payload
    end

    token.delete_prefix!('"')
    token.delete_suffix!('"')

    yield token
  end

  if !defined?(::ActionController::Parameters)
    # Get the request data. The keys inside the hash are symbols, so `params.keys` returns an array of `Symbol`.<br>
    # You can also load Strong Params to have Rage automatically wrap `params` in an instance of `ActionController::Parameters`.<br>
    # At the same time, if you are not implementing complex filtering rules or working with nested structures, consider using native `Hash#fetch` and `Hash#slice` instead.
    #
    # For multipart file uploads, the uploaded files are represented by an instance of {Rage::UploadedFile}.
    #
    # @return [Hash{Symbol=>String,Array,Hash,Numeric,NilClass,TrueClass,FalseClass}]
    # @example
    #   # make sure to load strong params before the `require "rage/all"` call
    #   require "active_support/all"
    #   require "action_controller/metal/strong_parameters"
    #
    #   params.permit(:user).require(:full_name, :dob)
    # @example
    #   # without strong params
    #   params.fetch(:user).slice(:full_name, :dob)
    def params
      @__params
    end
  else
    def params
      @params ||= ActionController::Parameters.new(@__params)
    end
  end

  # @private
  # for comatibility with `Rails.application.routes.recognize_path`
  def self.binary_params_for?(_)
    false
  end

  # @!method append_info_to_payload(payload)
  #   Override this method to add more information to request logs.
  #   @param [Hash] payload the payload to add additional information to
  #   @example
  #     def append_info_to_payload(payload)
  #       payload[:response] = response.body
  #     end
end

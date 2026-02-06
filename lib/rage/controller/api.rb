# frozen_string_literal: true

class RageController::API
  class << self
    # @private
    # used by the router to register a new action;
    # registering means defining a new method which calls the action, makes additional calls (e.g. before actions) and
    # sends a correct response down to the server;
    # returns the name of the newly defined method;
    # rubocop:disable Layout/IndentationWidth, Layout/EndAlignment, Layout/HeredocIndentation
    def __register_action(action)
      raise Rage::Errors::RouterError, "The action `#{action}` could not be found in the `#{self}` controller. This is likely due to route helpers pointing to non-existent actions in the controller. Please check your routes and ensure that all referenced actions exist." unless method_defined?(action)

      around_actions_total = 0

      before_actions_chunk = if @__before_actions
        lines = __before_actions_for(action).map do |h|
          condition = if h[:if] && h[:unless]
            "if #{h[:if]} && !#{h[:unless]}"
          elsif h[:if]
            "if #{h[:if]}"
          elsif h[:unless]
            "unless #{h[:unless]}"
          end

          if h[:around]
            around_actions_total += 1

            if condition
              <<~RUBY
                __should_apply_around_action = #{condition}
                  !@__before_callback_rendered
                end
                #{h[:wrapper]}(__should_apply_around_action) do
              RUBY
            else
              <<~RUBY
                __should_apply_around_action = !@__before_callback_rendered
                #{h[:wrapper]}(__should_apply_around_action) do
              RUBY
            end
          else
            <<~RUBY
              unless @__before_callback_rendered
                #{h[:name]} #{condition}
                @__before_callback_rendered = true if @__rendered
              end
            RUBY
          end
        end

        lines.join("\n")
      else
        ""
      end

      around_actions_end_chunk = around_actions_total.times.reduce("") { |memo| memo + "end\n" }

      after_actions_chunk = if @__after_actions
        lines = __after_actions_for(action).map do |h|
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
            #{instance_method(handler).arity == 0 ? handler : "#{handler}(__e)"}
            [@__status, @__headers, @__body]
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      wrap_parameters_chunk = if __wrap_parameters_key
        <<~RUBY
          wrap_key = self.class.__wrap_parameters_key
          if !@__params.key?(wrap_key) && @__env["CONTENT_TYPE"]
            wrap_options = self.class.__wrap_parameters_options
            wrapped_params = if wrap_options[:include].any?
                               @__params.slice(*wrap_options[:include])
                             else
                               params_to_exclude_by_default = %i[action controller]
                               @__params.except(*(wrap_options[:exclude] + params_to_exclude_by_default))
                             end

            @__params[wrap_key] = wrapped_params
          end
        RUBY
      end

      query_cache_enabled = defined?(::ActiveRecord)
      should_release_connections = Rage.config.internal.should_manually_release_ar_connections?

      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __run_#{action}
          Rage::Telemetry.tracer.span_controller_action_process(controller: self, params: @__params) do
            #{if query_cache_enabled
              <<~RUBY
                ActiveRecord::Base.connection_pool.enable_query_cache!
              RUBY
            end}

            #{wrap_parameters_chunk}
            #{before_actions_chunk}
            #{action} unless @__before_callback_rendered
            #{around_actions_end_chunk}

            #{if !after_actions_chunk.empty?
              <<~RUBY
                unless @__before_callback_rendered
                  @__rendered = true
                  #{after_actions_chunk}
                end
              RUBY
            end}

            [@__status, @__headers, @__body]

            #{rescue_handlers_chunk}

          ensure
            #{if query_cache_enabled
              <<~RUBY
                ActiveRecord::Base.connection_pool.disable_query_cache!
              RUBY
            end}

            #{if should_release_connections
              <<~RUBY
                ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
              RUBY
            end}

            #{if method_defined?(:append_info_to_payload) || private_method_defined?(:append_info_to_payload)
              <<~RUBY
                context = {}
                append_info_to_payload(context)

                log_context = Fiber[:__rage_logger_context]
                if log_context.empty?
                  Fiber[:__rage_logger_context] = context
                else
                  Fiber[:__rage_logger_context] = log_context.merge(context)
                end
              RUBY
            end}
          end
        end
      RUBY
    end
    # rubocop:enable all

    # @private
    attr_writer :__before_actions, :__after_actions, :__rescue_handlers
    # @private
    attr_accessor :__wrap_parameters_key, :__wrap_parameters_options

    # @private
    # pass the variable down to the child; the child will continue to use it until changes need to be made;
    # only then the object will be copied; the frozen state communicates that the object is shared with the parent;
    def inherited(klass)
      klass.__before_actions = @__before_actions.freeze
      klass.__after_actions = @__after_actions.freeze
      klass.__rescue_handlers = @__rescue_handlers.freeze
      klass.__wrap_parameters_key = __wrap_parameters_key
      klass.__wrap_parameters_options = __wrap_parameters_options
    end

    # @private
    @@__dynamic_name_seed = ("a".."i").to_a.permutation

    # @private
    # define a method based on a block
    def define_dynamic_method(block)
      name = @@__dynamic_name_seed.next.join
      define_method("__rage_dynamic_#{name}", block)
    end

    # @private
    # define a method that will call a specified method if a condition is `true` or yield if `false`
    def define_maybe_yield(method_name)
      name = @@__dynamic_name_seed.next.join

      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __rage_dynamic_#{name}(condition)
          if condition
            #{method_name} { yield }
          else
            yield
          end
        end
      RUBY
    end

    ############
    #
    # PUBLIC API
    #
    ############

    # Register a global exception handler. Handlers are inherited and matched from bottom to top.
    #
    # @param klasses [Class, Array<Class>] exception classes to watch on
    # @param with [Symbol] the name of a handler method. Alternatively, you can pass a block.
    # @example
    #   rescue_from User::NotAuthorized, with: :deny_access
    #
    #   def deny_access
    #     head :forbidden
    #   end
    # @example
    #   rescue_from User::NotAuthorized do |exception|
    #     render json: { message: exception.message }, status: :forbidden
    #   end
    def rescue_from(*klasses, with: nil, &block)
      unless with
        if block_given?
          with = define_dynamic_method(block)
        else
          raise ArgumentError, "No handler provided. Pass the `with` keyword argument or provide a block."
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
    # @param action_name [Symbol, nil] the name of the callback to add
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
      elsif (i = @__before_actions.find_index { |a| a[:name] == action_name })
        @__before_actions[i] = action
      else
        @__before_actions << action
      end
    end

    # Register a new `around_action` hook. Calls with the same `action_name` will overwrite the previous ones.
    #
    # @param action_name [Symbol, nil] the name of the callback to add
    # @param [Hash] opts action options
    # @option opts [Symbol, Array<Symbol>] :only restrict the callback to run only for specific actions
    # @option opts [Symbol, Array<Symbol>] :except restrict the callback to run for all actions except specified
    # @option opts [Symbol, Proc] :if only run the callback if the condition is true
    # @option opts [Symbol, Proc] :unless only run the callback if the condition is false
    # @example
    #   around_action :wrap_in_transaction
    #
    #   def wrap_in_transaction
    #     ActiveRecord::Base.transaction do
    #       yield
    #     end
    #   end
    def around_action(action_name = nil, **opts, &block)
      action = prepare_action_params(action_name, **opts, &block)
      action.merge!(around: true, wrapper: define_maybe_yield(action[:name]))

      if @__before_actions && @__before_actions.frozen?
        @__before_actions = @__before_actions.dup
      end

      if @__before_actions.nil?
        @__before_actions = [action]
      elsif (i = @__before_actions.find_index { |a| a[:name] == action_name })
        @__before_actions[i] = action
      else
        @__before_actions << action
      end
    end

    # Register a new `after_action` hook. Calls with the same `action_name` will overwrite the previous ones.
    #
    # @param action_name [Symbol, nil] the name of the callback to add
    # @param [Hash] opts action options
    # @option opts [Symbol, Array<Symbol>] :only restrict the callback to run only for specific actions
    # @option opts [Symbol, Array<Symbol>] :except restrict the callback to run for all actions except specified
    # @option opts [Symbol, Proc] :if only run the callback if the condition is true
    # @option opts [Symbol, Proc] :unless only run the callback if the condition is false
    # @example
    #   after_action :log_detailed_metrics, only: :create
    def after_action(action_name = nil, **opts, &block)
      action = prepare_action_params(action_name, **opts, &block)

      if @__after_actions && @__after_actions.frozen?
        @__after_actions = @__after_actions.dup
      end

      if @__after_actions.nil?
        @__after_actions = [action]
      elsif (i = @__after_actions.find_index { |a| a[:name] == action_name })
        @__after_actions[i] = action
      else
        @__after_actions << action
      end
    end

    # Prevent a `before_action` hook from running.
    #
    # @param action_name [Symbol] the name of the callback to skip
    # @param only [Symbol, Array<Symbol>] restrict the callback to be skipped only for specific actions
    # @param except [Symbol, Array<Symbol>] restrict the callback to be skipped for all actions except specified
    # @example
    #   skip_before_action :find_photo, only: :create
    def skip_before_action(action_name, only: nil, except: nil)
      i = @__before_actions&.find_index { |a| a[:name] == action_name && !a[:around] }
      raise ArgumentError, "The following action was specified to be skipped but couldn't be found: #{self}##{action_name}" unless i

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

    # Wraps the parameters hash into a nested hash. This will allow clients to submit requests without having to specify any root elements.
    # Params get wrapped only if the `Content-Type` header is present and the `params` hash doesn't contain a param with the same name as the wrapper key.
    #
    # @param key [Symbol] the wrapper key
    # @param include [Symbol, Array<Symbol>] the list of attribute names which parameters wrapper will wrap into a nested hash
    # @param exclude [Symbol, Array<Symbol>] the list of attribute names which parameters wrapper will exclude from a nested hash
    # @example
    #   wrap_parameters :user, include: %i[name age]
    # @example
    #   wrap_parameters :user, exclude: %i[address]
    def wrap_parameters(key, include: [], exclude: [])
      @__wrap_parameters_key = key
      @__wrap_parameters_options = { include:, exclude: }
    end

    # @private
    def __before_action_exists?(name)
      @__before_actions&.any? { |h| h[:name] == name && !h[:around] }
    end

    # @private
    def __before_actions_for(action_name)
      return [] unless @__before_actions

      @__before_actions.select do |h|
        (!h[:only] || h[:only].include?(action_name)) &&
          (!h[:except] || !h[:except].include?(action_name))
      end
    end

    # @private
    def __after_actions_for(action_name)
      return [] unless @__after_actions

      @__after_actions.select do |h|
        (!h[:only] || h[:only].include?(action_name)) &&
          (!h[:except] || !h[:except].include?(action_name))
      end
    end

    private

    # used by `before_action` and `after_action`
    def prepare_action_params(action_name = nil, **opts, &block)
      if block_given?
        action_name = define_dynamic_method(block)
      elsif action_name.nil?
        raise ArgumentError, "No handler provided. Pass the `action_name` parameter or provide a block."
      end

      _only, _except, _if, _unless = opts.values_at(:only, :except, :if, :unless)

      action = {
        name: action_name,
        only: _only && Array(_only),
        except: _except && Array(_except),
        if: _if,
        unless: _unless
      }

      action[:if] = define_dynamic_method(action[:if]) if action[:if].is_a?(Proc)
      action[:unless] = define_dynamic_method(action[:unless]) if action[:unless].is_a?(Proc)

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

  # @private
  attr_reader :__env, :__status, :__headers, :__body

  # Get the request object. See {Rage::Request}.
  # @return [Rage::Request]
  def request
    @request ||= Rage::Request.new(@__env, controller: self)
  end

  # Get the response object. See {Rage::Response}.
  # @return [Rage::Response]
  def response
    @response ||= Rage::Response.new(self)
  end

  # Get the cookie object. See {Rage::Cookies}.
  # @return [Rage::Cookies]
  def cookies
    @cookies ||= Rage::Cookies.new(@__env, @__headers)
  end

  # Get the session object. See {Rage::Session}.
  # @return [Rage::Session]
  def session
    @session ||= Rage::Session.new(cookies)
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
  # @return [Hash]
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

  # Authenticate using an HTTP Bearer token, or otherwise render an HTTP header requesting the client to send a
  # Bearer token. For the authentication to be considered successful, the block should return a non-nil value.
  #
  # @yield [token] token value extracted from the `Authorization` header
  # @example
  #   before_action :authenticate
  #
  #   def authenticate
  #     authenticate_or_request_with_http_token do |token|
  #       ApiToken.find_by(token: token)
  #     end
  #   end
  def authenticate_or_request_with_http_token
    authenticate_with_http_token { |token| yield(token) } || request_http_token_authentication
  end

  # Render an HTTP header requesting the client to send a Bearer token for authentication.
  def request_http_token_authentication
    headers["www-authenticate"] = "Token"
    render plain: "HTTP Token: Access denied.", status: 401
  end

  if !defined?(::ActionController::Parameters)
    # Get the request data. The keys inside the hash are symbols, so `params.keys` returns an array of `Symbol`.<br>
    # You can also load Strong Parameters to have Rage automatically wrap `params` in an instance of `ActionController::Parameters`.<br>
    # At the same time, if you are not implementing complex filtering rules or working with nested structures, consider using native `Hash#fetch` and `Hash#slice` instead.
    #
    # For multipart file uploads, the uploaded files are represented by an instance of {Rage::UploadedFile}.
    #
    # @return [Hash{Symbol=>String,Array,Hash,Numeric,NilClass,TrueClass,FalseClass}]
    # @example With Strong Parameters
    #   # in the Gemfile:
    #   gem "activesupport", require: "active_support/all"
    #   gem "actionpack", require: "action_controller/metal/strong_parameters"
    #
    #   # in the controller:
    #   params.require(:user).permit(:full_name, :dob)
    # @example Without Strong Parameters
    #   params.fetch(:user).slice(:full_name, :dob)
    def params
      @__params
    end
  else
    def params
      @__params__ ||= ActionController::Parameters.new(@__params)
    end
  end

  # Checks if the request is stale to decide if the action has to be rendered or the cached version is still valid. Use this method to implement conditional GET.
  #
  # @param etag [String] The etag of the requested resource.
  # @param last_modified [Time] The last modified time of the requested resource.
  # @return [Boolean] True if the response is stale, false otherwise.
  # @example
  #  stale?(etag: "123", last_modified: Time.utc(2023, 12, 15))
  #  stale?(last_modified: Time.utc(2023, 12, 15))
  #  stale?(etag: "123")
  # @note `stale?` will set ETag and Last-Modified response headers made of passed arguments in the method. Value for ETag will be additionally hashified using SHA1 algorithm, whereas value for Last-Modified will be converted to the string which represents time as RFC 1123 date of HTTP-date defined by RFC 2616.
  # @note `stale?` will set the response status to 304 if the request is fresh. This side effect will cause a double render error, if `render` gets called after this method. Make sure to implement a proper conditional in your action to prevent this from happening:
  #  ```ruby
  #  if stale?(etag: "123")
  #    render json: { hello: "world" }
  #  end
  #  ```
  def stale?(etag: nil, last_modified: nil)
    response.etag = etag
    response.last_modified = last_modified

    still_fresh = request.fresh?(etag: response.etag, last_modified: last_modified)

    head :not_modified if still_fresh
    !still_fresh
  end

  # Get the name of the currently executed action.
  # @return [String] the name of the currently executed action
  def action_name
    @__params[:action]
  end

  # @private
  # for comatibility with `Rails.application.routes.recognize_path`
  def self.binary_params_for?(_)
    false
  end

  # @!method append_info_to_payload(payload)
  #   Define this method to add more information to request logs.
  #   @param [Hash] payload the payload to add additional information to
  #   @example
  #     def append_info_to_payload(payload)
  #       payload[:response] = response.body
  #     end

  # Reset the entire session. See {Rage::Session}.
  def reset_session
    session.clear
  end
end

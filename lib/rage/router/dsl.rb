# frozen_string_literal: true

require_relative "dsl_plugins/legacy_hash_notation"
require_relative "dsl_plugins/legacy_root_notation"
require_relative "dsl_plugins/named_route_helpers"
require_relative "dsl_plugins/controller_action_options"

class Rage::Router::DSL
  def initialize(router)
    @router = router
  end

  def draw(&block)
    Handler.new(@router).instance_eval(&block)
    # propagate route definitions to Rails for `rails routes` to work
    Rails.application.routes.draw(&block) if Rage.config.internal.rails_mode
  end

  ##
  # This class implements routing logic for your application, providing an API similar to Rails.
  #
  # Compared to the Rails router, the most notable difference is that a wildcard segment can only be in the last section of the path and cannot be named.
  # Example:
  # ```ruby
  # get "/photos/*"
  # ```
  #
  # Also, as this is an API-only framework, route helpers, like `photos_path` or `photos_url` are not being generated.
  #
  # #### Constraints
  #
  # Currently, the only constraint supported is the `host` constraint. The constraint value can be either string or a regular expression.
  # Example:
  # ```ruby
  # get "/photos", to: "photos#index", constraints: { host: "myhost.com" }
  # ```
  #
  # Parameter constraints are likely to be added in the future versions. Custom/lambda constraints are unlikely to be ever added.
  #
  # @example Set up a root handler
  #   root to: "pages#main"
  # @example Set up multiple resources
  #   resources :magazines do
  #     resources :ads
  #   end
  # @example Scope a set of routes to the given default options.
  #   scope path: ":account_id" do
  #     resources :projects
  #   end
  # @example Scope routes to a specific namespace.
  #   namespace :admin do
  #     resources :posts
  #   end
  class Handler
    prepend Rage::Router::DSLPlugins::ControllerActionOptions
    prepend Rage::Router::DSLPlugins::NamedRouteHelpers
    prepend Rage::Router::DSLPlugins::LegacyHashNotation
    prepend Rage::Router::DSLPlugins::LegacyRootNotation

    # @private
    def initialize(router)
      @router = router

      @default_actions = %i(index create show update destroy)
      @default_actions += %i(new edit) if Rage.config.router.form_actions

      @default_match_methods = %i(get post put patch delete head)
      @scope_opts = %i(module path controller)

      @path_prefixes = []
      @module_prefixes = []
      @defaults = []
      @controllers = []
    end

    # Register a new GET route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param on [nil, :member, :collection] a shorthand for wrapping routes in a specific RESTful context
    # @example
    #   get "/photos/:id", to: "photos#show", constraints: { host: /myhost/ }
    # @example
    #   get "/photos(/:id)", to: "photos#show", defaults: { id: "-1" }
    def get(path, to: nil, constraints: nil, defaults: nil, on: nil)
      __with_on_scope(on) { __on("GET", path, to, constraints, defaults) }
    end

    # Register a new POST route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param on [nil, :member, :collection] a shorthand for wrapping routes in a specific RESTful context
    # @example
    #   post "/photos", to: "photos#create", constraints: { host: /myhost/ }
    # @example
    #   post "/photos", to: "photos#create", defaults: { format: "jpg" }
    def post(path, to: nil, constraints: nil, defaults: nil, on: nil)
      __with_on_scope(on) { __on("POST", path, to, constraints, defaults) }
    end

    # Register a new PUT route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param on [nil, :member, :collection] a shorthand for wrapping routes in a specific RESTful context
    # @example
    #   put "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    # @example
    #   put "/photos(/:id)", to: "photos#update", defaults: { id: "-1" }
    def put(path, to: nil, constraints: nil, defaults: nil, on: nil)
      __with_on_scope(on) { __on("PUT", path, to, constraints, defaults) }
    end

    # Register a new PATCH route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param on [nil, :member, :collection] a shorthand for wrapping routes in a specific RESTful context
    # @example
    #   patch "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    # @example
    #   patch "/photos(/:id)", to: "photos#update", defaults: { id: "-1" }
    def patch(path, to: nil, constraints: nil, defaults: nil, on: nil)
      __with_on_scope(on) { __on("PATCH", path, to, constraints, defaults) }
    end

    # Register a new DELETE route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param on [nil, :member, :collection] a shorthand for wrapping routes in a specific RESTful context
    # @example
    #   delete "/photos/:id", to: "photos#destroy", constraints: { host: /myhost/ }
    # @example
    #   delete "/photos(/:id)", to: "photos#destroy", defaults: { id: "-1" }
    def delete(path, to: nil, constraints: nil, defaults: nil, on: nil)
      __with_on_scope(on) { __on("DELETE", path, to, constraints, defaults) }
    end

    # Register a new route pointing to '/'.
    #
    # @param to [String] the route handler in the format of "controller#action"
    # @example
    #   root to: "photos#index"
    def root(to:)
      __on("GET", "/", to, nil, nil)
    end

    # Match a URL pattern to one or more routes.
    #
    # @param path [String] the path for the route handler
    # @param to [String, #call] the route handler in the format of "controller#action" or a callable
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param via [Symbol, Array<Symbol>] an array of HTTP methods to accept
    # @example
    #   match "/photos/:id", to: "photos#show", via: [:get, :post]
    # @example
    #   match "/photos/:id", to: "photos#show", via: :all
    # @example
    #   match "/health", to: -> (env) { [200, {}, ["healthy"]] }
    def match(path, to:, constraints: {}, defaults: nil, via: :all)
      # via is either nil, or an array of symbols or its :all
      http_methods = via
      # if its :all or nil, then we use the default HTTP methods
      if via == :all || via.nil?
        http_methods = @default_match_methods
      else
        # if its an array of symbols, then we use the symbols as HTTP methods
        http_methods = Array(via)
        # then we check if the HTTP methods are valid
        http_methods.each do |method|
          raise ArgumentError, "Invalid HTTP method: #{method}" unless @default_match_methods.include?(method)
        end
      end

      http_methods.each do |method|
        __on(method.to_s.upcase, path, to, constraints, defaults)
      end
    end

    # Register a new namespace.
    #
    # @param path [String] the path for the namespace
    # @param options [Hash] a hash of options for the namespace
    # @option options [String] :module the module name for the namespace
    # @option options [String] :path the path for the namespace
    # @example
    #   namespace :admin do
    #     get "/photos", to: "photos#index"
    #   end
    # @example
    #   namespace :admin, path: "panel" do
    #     get "/photos", to: "photos#index"
    #   end
    # @example
    #   namespace :admin, module: "admin" do
    #     get "/photos", to: "photos#index"
    #   end
    def namespace(path, **options, &block)
      path_prefix = options[:path] || path
      module_prefix = options[:module] || path

      @path_prefixes << path_prefix
      @module_prefixes << module_prefix

      instance_eval(&block)

      @path_prefixes.pop
      @module_prefixes.pop
    end

    # Scopes a set of routes to the given default options.
    #
    # @param [Hash] opts scope options.
    # @option opts [String] :module the namespace for the controller
    # @option opts [String] :path the path prefix for the routes
    # @option opts [String] :controller scopes routes to a specific controller
    # @example Route `/photos` to `Api::PhotosController`
    #   scope module: "api" do
    #     get "photos", to: "photos#index"
    #   end
    # @example Route `admin/photos` to `PhotosController`
    #   scope path: "admin" do
    #     get "photos", to: "photos#index"
    #   end
    # @example Route `/like` to `photos#like` and `/dislike` to `photos#dislike`
    #   scope controller: "photos" do
    #     post "like"
    #     post "dislike"
    #   end
    # @example Nested calls
    #   scope module: "admin" do
    #     get "photos", to: "photos#index"
    #
    #     scope path: "api", module: "api" do
    #       get "photos/:id", to: "photos#show"
    #     end
    #   end
    def scope(opts, &block)
      raise ArgumentError, "only :module, :path, and :controller options are accepted" if (opts.keys - @scope_opts).any?

      @path_prefixes << opts[:path].delete_prefix("/").delete_suffix("/") if opts[:path]
      @module_prefixes << opts[:module] if opts[:module]
      @controllers << opts[:controller] if opts[:controller]

      instance_eval(&block)

      @path_prefixes.pop if opts[:path]
      @module_prefixes.pop if opts[:module]
      @controllers.pop if opts[:controller]
    end

    # Specify default parameters for a set of routes.
    #
    # @param defaults [Hash] a hash of default parameters
    # @example
    #   defaults id: "-1", format: "jpg" do
    #     get "photos/(:id)", to: "photos#index"
    #   end
    def defaults(defaults, &block)
      @defaults << defaults
      instance_eval(&block)
      @defaults.pop
    end

    # Scopes routes to a specific controller.
    #
    # @example
    #   controller "photos" do
    #     post "like"
    #     post "dislike"
    #   end
    def controller(controller, &block)
      @controllers << controller
      instance_eval(&block)
      @controllers.pop
    end

    # Add a route to the collection.
    #
    # @example Add a `photos/search` path instead of `photos/:photo_id/search`
    #   resources :photos do
    #     collection do
    #       get "search"
    #     end
    #   end
    def collection(&block)
      orig_path_prefixes = @path_prefixes
      @path_prefixes = @path_prefixes[0...-1] if @path_prefixes.last&.start_with?(":")
      instance_eval(&block)
      @path_prefixes = orig_path_prefixes
    end

    # Add a member route.
    #
    # @example Add a `photos/:id/preview` path instead of `photos/:photo_id/preview`
    #   resources :photos do
    #     member do
    #       get "preview"
    #     end
    #   end
    def member(&block)
      orig_path_prefixes = @path_prefixes

      if (param_prefix = @path_prefixes.last)&.start_with?(":") && @controllers.any?
        member_prefix = param_prefix.delete_prefix(":#{to_singular(@controllers.last)}_")
        @path_prefixes = [*@path_prefixes[0...-1], ":#{member_prefix}"]
      end

      instance_eval(&block)

      @path_prefixes = orig_path_prefixes
    end

    # Automatically create REST routes for a resource.
    #
    # @param [Hash] opts resource options
    # @option opts [String] :module the namespace for the controller
    # @option opts [String] :path the path prefix for the routes
    # @option opts [Symbol, Array<Symbol>] :only only generate routes for the given actions
    # @option opts [Symbol, Array<Symbol>] :except generate all routes except for the given actions
    # @option opts [String] :param overrides the default param name of `:id` in the URL
    # @example Create five REST routes, all mapping to the `Photos` controller:
    #   resources :photos
    #   # GET       /photos       => photos#index
    #   # POST      /photos       => photos#create
    #   # GET       /photos/:id   => photos#show
    #   # PATCH/PUT /photos/:id   => photos#update
    #   # DELETE    /photos/:id   => photos#destroy
    # @note This helper doesn't generate the `new` and `edit` routes.
    def resources(*_resources, **opts, &block)
      # support calls with multiple resources, e.g. `resources :albums, :photos`
      if _resources.length > 1
        _resources.each { |_resource| resources(_resource, **opts, &block) }
        return
      end

      _module, _path, _only, _except, _param = opts.values_at(:module, :path, :only, :except, :param)
      raise ArgumentError, ":param option can't contain colons" if _param.to_s.include?(":")

      actions = __filter_actions(@default_actions, _only, _except)

      resource = _resources[0].to_s
      _param ||= "id"

      __resource_scope(resource, _path, _module) do
        get("/", to: "#{resource}#index") if actions.include?(:index)
        post("/", to: "#{resource}#create") if actions.include?(:create)
        get("/:#{_param}", to: "#{resource}#show") if actions.include?(:show)
        patch("/:#{_param}", to: "#{resource}#update") if actions.include?(:update)
        put("/:#{_param}", to: "#{resource}#update") if actions.include?(:update)
        get("/new", to: "#{resource}#new") if actions.include?(:new)
        get("/:#{_param}/edit", to: "#{resource}#edit") if actions.include?(:edit)
        delete("/:#{_param}", to: "#{resource}#destroy") if actions.include?(:destroy)

        scope(path: ":#{to_singular(resource)}_#{_param}", controller: resource, &block) if block
      end
    end

    # Automatically create REST routes for a singular resource.
    #
    # @param [Hash] opts resource options
    # @option opts [String] :module the namespace for the controller
    # @option opts [String] :path the path prefix for the routes
    # @option opts [Symbol, Array<Symbol>] :only only generate routes for the given actions
    # @option opts [Symbol, Array<Symbol>] :except generate all routes except for the given actions
    # @example Create singular routes mapped to a plural controller:
    #   resource :photo
    #   # POST   /photo => photos#create
    #   # GET    /photo => photos#show
    #   # PATCH  /photo => photos#update
    #   # PUT    /photo => photos#update
    #   # DELETE /photo => photos#destroy
    # @note :param is not supported for singular resources.
    def resource(*_resources, **opts, &block)
      if _resources.length > 1
        _resources.each { |_resource| resource(_resource, **opts, &block) }
        return
      end

      _module, _path, _only, _except = opts.values_at(:module, :path, :only, :except)

      actions = __filter_actions(@default_actions - [:index], _only, _except)

      resource_name = _resources[0].to_s
      controller_name = to_plural(resource_name)
      __resource_scope(resource_name, _path, _module) do
        post("/", to: "#{controller_name}#create") if actions.include?(:create)
        get("/", to: "#{controller_name}#show") if actions.include?(:show)
        patch("/", to: "#{controller_name}#update") if actions.include?(:update)
        put("/", to: "#{controller_name}#update") if actions.include?(:update)
        get("/new", to: "#{controller_name}#new") if actions.include?(:new)
        get("/edit", to: "#{controller_name}#edit") if actions.include?(:edit)
        delete("/", to: "#{controller_name}#destroy") if actions.include?(:destroy)

        scope(controller: controller_name, &block) if block
      end
    end

    # Mount a Rack-based application to be used within the application.
    #
    # @example
    #   mount Sidekiq::Web => "/sidekiq"
    # @example
    #   mount Sidekiq::Web, at: "/sidekiq", via: :get
    def mount(app, at:, via: :all)
      at = "/#{at}" unless at.start_with?("/")
      at = at.delete_suffix("/") if at.end_with?("/")

      http_methods = if via == :all || via.nil?
        @default_match_methods.map { |method| method.to_s.upcase! }
      else
        Array(via).map! do |method|
          raise ArgumentError, "Invalid HTTP method: #{method}" unless @default_match_methods.include?(method)
          method.to_s.upcase!
        end
      end

      @router.mount(at, app, http_methods)
    end

    private

    def __on(method, path, to, constraints, defaults)
      # handle calls without controller inside resources:
      #   resources :comments do
      #     post :like
      #   end
      if !to
        if @controllers.any?
          to = "#{@controllers.last}##{path}"
        else
          raise ArgumentError, "Missing :to key on routes definition, please check your routes."
        end
      end

      # process path to ensure it starts with "/" and doesn't end with "/"
      if path != "/"
        path = "/#{path}" unless path.start_with?("/")
        path = path.delete_suffix("/") if path.end_with?("/")
      end

      # correctly process root helpers inside `scope` calls
      if path == "/" && @path_prefixes.any?
        path = ""
      end

      path_prefix = @path_prefixes.any? ? "/#{@path_prefixes.join("/")}" : nil
      module_prefix = @module_prefixes.any? ? "#{@module_prefixes.join("/")}/" : nil
      defaults = (defaults ? @defaults + [defaults] : @defaults).reduce(&:merge)

      if to.is_a?(String)
        @router.on(method, "#{path_prefix}#{path}", "#{module_prefix}#{to}", constraints: constraints || {}, defaults: defaults)
      else
        @router.on(method, "#{path_prefix}#{path}", to, constraints: constraints || {}, defaults: defaults)
      end
    end

    def __with_on_scope(on, &block)
      case on
      when nil
        block.call
      when :member
        member(&block)
      when :collection
        collection(&block)
      else
        raise ArgumentError, "Unknown scope :#{on} given to :on"
      end
    end

    # Filters a list of actions based on :only and :except options
    def __filter_actions(default_actions, only, except)
      only = Array(only) if only
      except = Array(except) if except

      default_actions.select do |action|
        (only.nil? || only.include?(action)) &&
          (except.nil? || !except.include?(action))
      end
    end

    # Wraps route definitions in the correct path/module scope
    def __resource_scope(resource, path, mod, &block)
      path ||= resource
      scope_opts = { path: path }
      scope_opts[:module] = mod if mod
      scope(scope_opts, &block)
    end

    def to_singular(str)
      @active_support_loaded ||= str.respond_to?(:singularize) || :false
      return str.singularize if @active_support_loaded != :false

      @endings ||= {
        "ves" => "fe",
        "ies" => "y",
        "i" => "us",
        "zes" => "ze",
        "ses" => "s",
        "es" => "",
        "s" => ""
      }
      @regexp ||= Regexp.new("(#{@endings.keys.join("|")})$")

      str.sub(@regexp, @endings)
    end

    def to_plural(str)
      @active_support_loaded ||= str.respond_to?(:pluralize) || :false
      return str.pluralize if @active_support_loaded != :false

      str.end_with?("s") ? str : "#{str}s"
    end
  end
end

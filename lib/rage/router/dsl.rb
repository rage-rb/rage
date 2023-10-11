# frozen_string_literal: true

class Rage::Router::DSL
  def initialize(router)
    @router = router
  end

  def draw(&block)
    Handler.new(@router).instance_eval(&block)
  end

  class Handler
    # @private
    def initialize(router)
      @router = router

      @path_prefixes = []
      @module_prefixes = []
      @defaults = []
    end

    # Register a new GET route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @example
    #   get "/photos/:id", to: "photos#show", constraints: { host: /myhost/ }
    # @example
    #   get "/photos(/:id)", to: "photos#show", defaults: { id: "-1" }
    def get(path, to:, constraints: nil, defaults: nil)
      __on("GET", path, to, constraints, defaults)
    end

    # Register a new POST route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @example
    #   post "/photos", to: "photos#create", constraints: { host: /myhost/ }
    # @example
    #   post "/photos", to: "photos#create", defaults: { format: "jpg" }
    def post(path, to:, constraints: nil, defaults: nil)
      __on("POST", path, to, constraints, defaults)
    end

    # Register a new PUT route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @example
    #   put "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    # @example
    #   put "/photos(/:id)", to: "photos#update", defaults: { id: "-1" }
    def put(path, to:, constraints: nil, defaults: nil)
      __on("PUT", path, to, constraints, defaults)
    end

    # Register a new PATCH route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @example
    #   patch "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    # @example
    #   patch "/photos(/:id)", to: "photos#update", defaults: { id: "-1" }
    def patch(path, to:, constraints: nil, defaults: nil)
      __on("PATCH", path, to, constraints, defaults)
    end

    # Register a new DELETE route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @example
    #   delete "/photos/:id", to: "photos#destroy", constraints: { host: /myhost/ }
    # @example
    #   delete "/photos(/:id)", to: "photos#destroy", defaults: { id: "-1" }
    def delete(path, to:, constraints: nil, defaults: nil)
      __on("DELETE", path, to, constraints, defaults)
    end

    # Register a new route pointing to '/'.
    #
    # @param to [String] the route handler in the format of "controller#action"
    # @example
    #   root to: "photos#index"
    def root(to:)
      __on("GET", "/", to, nil, nil)
    end

    # Scopes a set of routes to the given default options.
    #
    # @param [Hash] opts scope options.
    # @option opts [String] :module module option
    # @option opts [String] :path path option
    # @example Route `/photos` to `Api::PhotosController`
    #   scope module: "api" do
    #     get "photos", to: "photos#index"
    #   end
    # @example Route `admin/photos` to `PhotosController`
    #   scope path: "admin" do
    #     get "photos", to: "photos#index"
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
      raise ArgumentError, "only 'module' and 'path' options are accepted" if (opts.keys - %i(module path)).any?

      @path_prefixes << opts[:path].delete_prefix("/").delete_suffix("/") if opts[:path]
      @module_prefixes << opts[:module] if opts[:module]

      instance_eval &block

      @path_prefixes.pop if opts[:path]
      @module_prefixes.pop if opts[:module]
    end

    def resources(name, opts = {})
      @path_prefixes << name.to_s

      yield if block_given?

      @path_prefixes.pop

      default_resource_actions = %i(index show create update destroy)
      only = opts[:only]
      except = opts[:except]
      constraints = opts[:constraints]
      defaults = opts[:defaults]

      raise ArgumentError, "only one of 'only' and 'except' options can be specified" if only && except

      routes = []
      if only
        routes = only
        routes.each do |route|
          raise ArgumentError, "Bad resource route: #{route} for only option" unless default_resource_actions.include?(route)
        end
      elsif except
        routes = default_resource_actions - except.map(&:to_sym)
      else
        routes = default_resource_actions
      end

      routes.each do |route|
        case route
        when :index
          __on("GET", "#{name}", "#{name}#index", constraints, defaults)
        when :show
          __on("GET", "#{name}/:id", "#{name}#show", constraints, defaults)
        when :create
          __on("POST", "#{name}", "#{name}#create", constraints, defaults)
        when :update
          __on("PUT", "#{name}/:id", "#{name}#update", constraints, defaults)
        when :destroy
          __on("DELETE", "#{name}/:id", "#{name}#destroy", constraints, defaults)
        end
      end
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
      instance_eval &block
      @defaults.pop
    end

    private

    def __on(method, path, to, constraints, defaults)
      if path != "/"
        path = "/#{path}" unless path.start_with?("/")
        path = path.delete_suffix("/") if path.end_with?("/")
      end

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
  end
end

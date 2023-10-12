# frozen_string_literal: true

class Rage::Router::DSL
  def initialize(router)
    @router = router
  end

  def draw(&block)
    Handler.new(@router).instance_eval(&block)
  end

  class Handler
    DEFAULT_MATCH_METHODS = %w[get post put patch delete].freeze
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

    #  Register a new route that accepts any HTTP method.
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @param defaults [Hash] a hash of default parameters for the route
    # @param via [Symbol, Array<Symbol>] an array of HTTP methods to accept
    # @example
    #   match "/photos/:id", to: "photos#show", via: ["get", "post"]
    # @example
    #   match "/photos/:id", to: "photos#show", via: :all
    def match(path, to:, constraints: {}, defaults: nil, via: :all)
      # via is either nil, or an array of symbols or its :all
      http_methods = via
      # if its :all or nil, then we use the default HTTP methods
      if [nil, :all].include?(via)
        http_methods = DEFAULT_MATCH_METHODS
      else
        # if its an array of symbols, then we use the symbols as HTTP methods
        http_methods = Array(via).flatten.map(&:to_s)
        # then we check if the HTTP methods are valid
        http_methods.each do |method|
          raise ArgumentError, "Invalid HTTP method: #{method}" unless DEFAULT_MATCH_METHODS.include?(method)
        end
      end

      http_methods.each do |method|
        __on(method.upcase, path, to, constraints, defaults)
      end
    end

    def namespace(path, &block)
      @path_prefixes << path
      @module_prefixes << path

      instance_eval &block

      @path_prefixes.pop
      @module_prefixes.pop
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

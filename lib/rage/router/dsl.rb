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
    end

    # Register a new GET route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @example
    #   get "/photos/:id", to: "photos#show", constraints: { host: /myhost/ }
    def get(path, to:, constraints: nil)
      __on("GET", path, to, constraints)
    end

    # Register a new POST route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @example
    #   post "/photos", to: "photos#create", constraints: { host: /myhost/ }
    def post(path, to:, constraints: nil)
      __on("POST", path, to, constraints)
    end

    # Register a new PUT route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @example
    #   put "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    def put(path, to:, constraints: nil)
      __on("PUT", path, to, constraints)
    end

    # Register a new PATCH route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @example
    #   patch "/photos/:id", to: "photos#update", constraints: { host: /myhost/ }
    def patch(path, to:, constraints: nil)
      __on("PATCH", path, to, constraints)
    end

    # Register a new DELETE route.
    #
    # @param path [String] the path for the route handler
    # @param to [String] the route handler in the format of "controller#action"
    # @param constraints [Hash] a hash of constraints for the route
    # @example
    #   delete "/photos/:id", to: "photos#destroy", constraints: { host: /myhost/ }
    def delete(path, to:, constraints: nil)
      __on("DELETE", path, to, constraints)
    end

    # Register a new route pointing to '/'.
    #
    # @param to [String] the route handler in the format of "controller#action"
    # @example
    #   root to: "photos#index"
    def root(to:)
      __on("GET", "/", to, nil)
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

    private

    def __on(method, path, to, constraints)
      if path != "/"
        path = "/#{path}" unless path.start_with?("/")
        path = path.delete_suffix("/") if path.end_with?("/")
      end

      if path == "/" && @path_prefixes.any?
        path = ""
      end

      path_prefix = @path_prefixes.any? ? "/#{@path_prefixes.join("/")}" : nil
      module_prefix = @module_prefixes.any? ? "#{@module_prefixes.join("/")}/" : nil

      if to.is_a?(String)
        @router.on(method, "#{path_prefix}#{path}", "#{module_prefix}#{to}", constraints: constraints || {})
      else
        @router.on(method, "#{path_prefix}#{path}", to, constraints: constraints || {})
      end
    end
  end
end

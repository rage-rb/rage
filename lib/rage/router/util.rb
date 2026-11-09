# frozen_string_literal: true

class Rage::Router::Util
  class << self
    # converts controller name in a path form into a class
    # `api/v1/users` => `Api::V1::UsersController`
    def path_to_class(str)
      str = str.capitalize
      str.gsub!(/([\/_])([a-zA-Z0-9]+)/) do
        if $1 == "/"
          "::#{$2.capitalize}"
        else
          $2.capitalize
        end
      end

      klass = "#{str}Controller"
      if Object.const_defined?(klass)
        Object.const_get(klass)
      else
        raise Rage::Errors::RouterError, "Routing error: could not find the #{klass} class"
      end
    end

    @@names_map = {}

    # converts controller name in a path form into a string representation of a class
    # `api/v1/users` => `"Api::V1::UsersController"`
    def path_to_name(str)
      @@names_map[str] || begin
        @@names_map[str] = path_to_class(str).name
      end
    end

    @@uri_patterns_map = Hash.new { |h, k| h[k] = {} }

    def route_uri_pattern(controller_class, action_name)
      @@uri_patterns_map[controller_class][action_name] ||= Rage.__router.routes.find { |route|
        route[:meta][:controller_class] == controller_class && route[:meta][:action] == action_name
      }[:path]
    end

    @@path_builders = Hash.new { |h, k| h[k] = {} }

    # Generates a URL path for the specified controller and action.
    #
    # @param controller [String] the controller name in path form (e.g., "users", "api/v1/photos")
    # @param action [String] the action name (e.g., "show", "index")
    # @param params [Hash] route parameters to substitute into the path
    # @return [String] the generated path
    # @raise [ArgumentError] if no route is defined for the controller/action pair,
    #   or if the provided params don't match any available route
    #
    # @note For wildcard routes (e.g., `/files/*`), use the `wildcard:` keyword argument.
    #
    # @example Basic usage
    #   path_for(controller: "users", action: "show", id: 1)
    #   # => "/users/1"
    #
    # @example With nested resource
    #   path_for(controller: "posts", action: "show", user_id: 1, id: 42)
    #   # => "/users/1/posts/42"
    #
    # @example With wildcard route
    #   path_for(controller: "files", action: "show", wildcard: "path/to/file.txt")
    #   # => "/files/path/to/file.txt"
    #
    def path_for(controller:, action:, **params)
      path_builders = path_builders_for(controller, action)

      path_builder = if path_builders.size == 1
        path_builders[0]
      else
        path_builders.find { |pb|
          pb.parameters.size == params.size && params.except(*pb.parameters.map(&:last)).empty?
        } || raise(ArgumentError, "No matching route for '#{controller}##{action}' with params #{params.keys}")
      end

      path_builder.call(**params)
    end

    private

    def path_builders_for(controller, action)
      @@path_builders[controller][action] ||= begin
        routes = Rage.__router.routes.select { |r| r[:meta][:controller] == controller && r[:meta][:action] == action }
        raise ArgumentError, "No route defined for '#{controller}##{action}'" if routes.empty?

        routes.map do |route|
          path_pattern = route[:path]
          params = route[:params].map { |param| param == "*" ? "wildcard" : param }

          eval <<~RUBY
            -> (#{params.map { |param| "#{param}:" }.join(", ")}) do
              args = [#{params.join(", ")}].each
              "#{path_pattern}".gsub(/(:\\w+|\\*)/) { args.next }
            end
          RUBY
        end
      end
    end
  end

  # @private
  class Cascade
    def initialize(rage_app, rails_app)
      @rage_app = rage_app
      @rails_app = rails_app
    end

    def call(env)
      result = @rage_app.call(env)
      return result if result[0] == :__http_defer__

      if result[1]["X-Cascade"] == "pass" || env["PATH_INFO"].start_with?("/rails/")
        @rails_app.call(env)
      else
        result
      end
    end
  end
end

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
  end
end

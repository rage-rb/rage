# frozen_string_literal: true

require "uri"

class Rage::Router::Backend
  attr_reader :routes

  OPTIONAL_PARAM_REGEXP = /\/?\(\/?(:\w+)\/?\)/
  STRING_HANDLER_REGEXP = /^([a-z0-9_\/]+)#([a-z_]+)$/

  def initialize
    @routes = []
    @trees = {}
    @constrainer = Rage::Router::Constrainer.new({})
  end

  def reset_routes
    @routes = []
    @trees = {}
  end

  def mount(path, handler, methods)
    raise ArgumentError, "Mount handler should respond to `call`" unless handler.respond_to?(:call)

    raw_handler = handler.respond_to?(:__rage_root_app) ? handler.__rage_root_app : handler

    handler = if handler.respond_to?(:name) && handler.name == "Sidekiq::Web"
      wrap_in_rack_session(handler)
    else
      raw_handler
    end

    app = ->(env, _params) do
      # rewind `rack.input` in case mounted application needs to access the request body;
      # by the time the app is called, `rack.input` is already consumed in `Rage::ParamsParser`
      env["rack.input"].rewind

      env["SCRIPT_NAME"] = path
      sub_path = env["PATH_INFO"].delete_prefix!(path)
      env["PATH_INFO"] = "/" if sub_path == ""

      handler.call(env)
    ensure
      env["PATH_INFO"] = "#{env["SCRIPT_NAME"]}#{sub_path}"
    end

    methods.each do |method|
      __on(method, path, app, {}, {}, { raw_handler:, mount: true })
      __on(method, "#{path}/*", app, {}, {}, { raw_handler:, mount: true })
    end
  end

  def on(method, path, handler, constraints: {}, defaults: nil)
    raise "Path could not be empty" if path&.empty?

    if (match_index = (path =~ OPTIONAL_PARAM_REGEXP))
      raise ArgumentError, "Optional Parameter has to be the last parameter of the path" if path.length != match_index + $&.length

      path_full = path.sub(OPTIONAL_PARAM_REGEXP, "/#{$1}")
      path_optional = path.sub(OPTIONAL_PARAM_REGEXP, "")

      on(method, path_full, handler, constraints: constraints, defaults: defaults)
      on(method, path_optional, handler, constraints: constraints, defaults: defaults)
      return
    end

    meta = { raw_handler: handler }

    if handler.is_a?(String)
      raise ArgumentError, "Invalid route handler format, expected to match the 'controller#action' pattern" unless handler =~ STRING_HANDLER_REGEXP

      controller, action = Rage::Router::Util.path_to_class($1), $2

      if controller.ancestors.include?(RageController::API)
        run_action_method_name = controller.__register_action(action.to_sym)

        meta[:controller] = $1
        meta[:action] = $2
        meta[:controller_class] = controller

        handler = eval("->(env, params) { #{controller}.new(env, params).#{run_action_method_name} }")
      else
        # this is a Rails controller; notify `Rage::Router::Util::Cascade` to forward the request to Rails
        handler = ->(_, _) { [404, { "X-Cascade" => "pass" }, []] }
      end
    else
      raise ArgumentError, "Non-string route handler should respond to `call`" unless handler.respond_to?(:call)
      # while regular handlers are expected to be called with the `env` and `params` objects,
      # lambda handlers expect just `env` as an argument;
      # TODO: come up with something nicer?
      orig_handler = handler
      handler = ->(env, _params) { orig_handler.call(env) }
    end

    __on(method, path, handler, constraints, defaults, meta)

  rescue Rage::Errors::RouterError => e
    raise e unless Rage.code_loader.reloading?
  end

  def lookup(env)
    constraints = @constrainer.derive_constraints(env)
    find(env, constraints)
  end

  private

  def __on(method, path, handler, constraints, defaults, meta)
    @constrainer.validate_constraints(constraints)
    # Let the constrainer know if any constraints are being used now
    @constrainer.note_usage(constraints)

    # Boot the tree for this method if it doesn't exist yet
    @trees[method] ||= Rage::Router::StaticNode.new("/")

    pattern = path
    if pattern == "*" && !@trees[method].prefix.empty?
      current_root = @trees[method]
      @trees[method] = Rage::Router::StaticNode.new("")
      @trees[method].static_children["/"] = current_root
    end

    current_node = @trees[method]
    parent_node_path_index = current_node.prefix.length

    i, params = 0, []
    while i <= pattern.length
      if pattern[i] == ":" && pattern[i + 1] == ":"
        # It's a double colon
        i += 2
        next
      end

      is_parametric_node = pattern[i] == ":" && pattern[i + 1] != ":"
      is_wildcard_node = pattern[i] == "*"

      if is_parametric_node || is_wildcard_node || (i == pattern.length && i != parent_node_path_index)
        static_node_path = pattern[parent_node_path_index, i - parent_node_path_index]
        static_node_path = static_node_path.split("::").join(":")
        static_node_path = static_node_path.split("%").join("%25")
        # add the static part of the route to the tree
        current_node = current_node.create_static_child(static_node_path)
      end

      if is_parametric_node
        last_param_start_index = i + 1

        j = last_param_start_index
        while true
          char = pattern[j]
          is_end_of_node = (char == "/" || j == pattern.length)

          if is_end_of_node
            param_name = pattern[last_param_start_index, j - last_param_start_index]
            params << param_name

            static_part_start_index = j
            while j < pattern.length
              j_char = pattern[j]
              break if j_char == "/"
              if j_char == ":"
                next_char = pattern[j + 1]
                next_char == ":" ? j += 1 : break
              end
              j += 1
            end

            static_part = pattern[static_part_start_index, j - static_part_start_index]
            unless static_part.empty?
              static_part = static_part.split("::").join(":")
              static_part = static_part.split("%").join("%25")
            end

            last_param_start_index = j + 1

            if is_end_of_node || pattern[j] == "/" || j == pattern.length
              node_path = pattern[i, j - i]

              pattern = "#{pattern[0, i + 1]}#{static_part}#{pattern[j, pattern.length - j]}"
              i += static_part.length

              current_node = current_node.create_parametric_child(static_part == "" ? nil : static_part, node_path)
              parent_node_path_index = i + 1
              break
            end
          end

          j += 1
        end
      elsif is_wildcard_node
        # add the wildcard parameter
        params << "*"
        current_node = current_node.create_wildcard_child
        parent_node_path_index = i + 1
        raise ArgumentError, "Wildcard must be the last character in the route" if i != pattern.length - 1
      end

      i += 1
    end

    if pattern == "*"
      pattern = "/*"
    end

    @routes.each do |existing_route|
      if existing_route[:method] == method &&
         existing_route[:pattern] == pattern &&
         existing_route[:constraints] == constraints
        raise ArgumentError, "Method '#{method}' already declared for route '#{pattern}' with constraints '#{constraints.inspect}'"
      end
    end

    route = { method:, path:, pattern:, params:, constraints:, handler:, defaults:, meta: }
    @routes << route
    current_node.add_route(route, @constrainer)
  end

  def find(env, derived_constraints)
    method, path = env["REQUEST_METHOD"], env["PATH_INFO"]
    path.delete_suffix!("/") if path.end_with?("/") && path.length > 1

    current_node = @trees[method]
    return nil unless current_node

    origin_path = path

    path_index = current_node.prefix.length
    url_params = []
    path_len = path.length

    brothers_nodes_stack = []

    while true
      if path_index == path_len && current_node.is_leaf_node
        handle = current_node.handler_storage.get_matching_handler(derived_constraints)
        if handle
          return {
            handler: handle[:handler],
            params: handle[:create_params_object].call(url_params)
          }
        end
      end

      node = current_node.get_next_node(path, path_index, brothers_nodes_stack, url_params.length)

      unless node
        return if brothers_nodes_stack.length == 0

        brother_node_state = brothers_nodes_stack.pop
        path_index = brother_node_state[:brother_path_index]
        url_params.slice!(brother_node_state[:params_count], url_params.length)
        node = brother_node_state[:brother_node]
      end

      current_node = node

      if current_node.kind == Rage::Router::Node::STATIC
        path_index += current_node.prefix.length
        next
      end

      if current_node.kind == Rage::Router::Node::WILDCARD
        param = origin_path[path_index, origin_path.length - path_index]
        param = Rack::Utils.unescape(param) if param.include?("%")

        url_params << param
        path_index = path_len
        next
      end

      if current_node.kind == Rage::Router::Node::PARAMETRIC
        param_end_index = origin_path.index("/", path_index)
        param_end_index = path_len unless param_end_index

        param = origin_path.slice(path_index, param_end_index - path_index)
        param = Rack::Utils.unescape(param) if param.include?("%")

        url_params << param
        path_index = param_end_index
      end
    end
  end

  def wrap_in_rack_session(handler)
    unless defined?(Rack::Session::Cookie)
      fail <<~ERR

        `#{handler.name}` depends on `Rack::Session`. Ensure the following line is added to your Gemfile:
        gem "rack-session"

      ERR
    end

    secret_key = if Rage.config.secret_key_base
      require "openssl"
      OpenSSL::KDF.hkdf(
        [Rage.config.secret_key_base].pack("H*"),
        salt: "rack.session",
        info: handler.name,
        length: 64,
        hash: "SHA256"
      )
    else
      puts "WARNING: `secret_key_base` is not set. Using a temporary random secret for `#{handler.name}` sessions. Sessions will not persist across server restarts."
      require "securerandom"
      SecureRandom.random_bytes(64)
    end

    Rack::Session::Cookie.new(handler, secret: secret_key, same_site: true, max_age: 86400)
  end
end

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

  def mount(path, handler, methods)
    raise "Mount handler should respond to `call`" unless handler.respond_to?(:call)

    raw_handler = handler
    is_sidekiq = handler.respond_to?(:name) && handler.name == "Sidekiq::Web"

    handler = ->(env, _params) do
      env["SCRIPT_NAME"] = path
      sub_path = env["PATH_INFO"].delete_prefix!(path)
      env["PATH_INFO"] = "/" if sub_path == ""

      if is_sidekiq
        Rage::SidekiqSession.with_session(env) do
          raw_handler.call(env)
        end
      else
        raw_handler.call(env)
      end
    end

    methods.each do |method|
      __on(method, path, handler, raw_handler, {}, nil)
      __on(method, "#{path}/*", handler, raw_handler, {}, nil)
    end
  end

  def on(method, path, handler, constraints: {}, defaults: nil)
    raw_handler = handler
    raise "Path could not be empty" if path&.empty?

    if match_index = (path =~ OPTIONAL_PARAM_REGEXP)
      raise "Optional Parameter has to be the last parameter of the path" if path.length != match_index + $&.length

      path_full = path.sub(OPTIONAL_PARAM_REGEXP, "/#{$1}")
      path_optional = path.sub(OPTIONAL_PARAM_REGEXP, "")

      on(method, path_full, handler, constraints: constraints, defaults: defaults)
      on(method, path_optional, handler, constraints: constraints, defaults: defaults)
      return
    end

    if handler.is_a?(String)
      raise "Invalid route handler format, expected to match the 'controller#action' pattern" unless handler =~ STRING_HANDLER_REGEXP

      controller, action = to_controller_class($1), $2
      run_action_method_name = controller.__register_action(action.to_sym)

      handler = eval("->(env, params) { #{controller}.new(env, params).#{run_action_method_name} }")
    else
      raise "Non-string route handler should respond to `call`" unless handler.respond_to?(:call)
      # while regular handlers are expected to be called with the `env` and `params` objects,
      # lambda handlers expect just `env` as an argument;
      # TODO: come up with something nicer?
      orig_handler = handler
      handler = ->(env, _params) { orig_handler.call(env) }
    end

    __on(method, path, handler, raw_handler, constraints, defaults)
  end

  def lookup(env)
    constraints = @constrainer.derive_constraints(env)
    find(env, constraints)
  end

  private

  def __on(method, path, handler, raw_handler, constraints, defaults)
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
        raise "Wildcard must be the last character in the route" if i != pattern.length - 1
      end

      i += 1
    end

    if pattern == "*"
      pattern = "/*"
    end

    @routes.each do |existing_route|
      if (
        existing_route[:method] == method &&
        existing_route[:pattern] == pattern &&
        existing_route[:constraints] == constraints
      )
        raise "Method '#{method}' already declared for route '#{pattern}' with constraints '#{constraints.inspect}'"
      end
    end

    route = { method: method, path: path, pattern: pattern, params: params, constraints: constraints, handler: handler, raw_handler: raw_handler, defaults: defaults }
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

  def to_controller_class(str)
    str.capitalize!
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
      raise "Routing error: could not find the #{klass} class"
    end
  end
end

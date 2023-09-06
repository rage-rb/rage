# frozen_string_literal: true

require "set"

module Rage::Router
  class Node
    STATIC = 0
    PARAMETRIC = 1
    WILDCARD = 2

    attr_reader :is_leaf_node, :handler_storage, :kind

    def initialize
      @is_leaf_node = false
      @routes = nil
      @handler_storage = nil
    end

    def add_route(route, constrainer)
      @routes ||= []
      @handler_storage ||= HandlerStorage.new

      @is_leaf_node = true
      @routes << route
      @handler_storage.add_handler(constrainer, route)
    end
  end

  class ParentNode < Node
    attr_reader :static_children

    def initialize
      super
      @static_children = {}
    end

    def find_static_matching_child(path, path_index)
      static_child = @static_children[path[path_index]]

      if !static_child || !static_child.match_prefix.call(path, path_index)
        return nil
      end

      static_child
    end

    def create_static_child(path)
      if path.length == 0
        return self
      end

      static_child = @static_children[path[0]]
      if static_child
        i = 1
        while i < static_child.prefix.length
          if path[i] != static_child.prefix[i]
            static_child = static_child.split(self, i)
            break
          end
          i += 1
        end

        return static_child.create_static_child(path[i, path.length - i])
      end

      @static_children[path[0]] = StaticNode.new(path)
    end
  end

  class StaticNode < ParentNode
    attr_reader :prefix, :match_prefix

    def initialize(prefix)
      super()
      @prefix = prefix
      @wildcard_child = nil
      @parametric_children = []
      @kind = Node::STATIC

      compile_prefix_match
    end

    def create_parametric_child(static_suffix, node_path)
      parametric_child = @parametric_children[0]

      if parametric_child
        parametric_child.node_paths.add(node_path)
        return parametric_child
      end

      parametric_child = ParametricNode.new(static_suffix, node_path)
      @parametric_children << parametric_child
      @parametric_children.sort! do |child1, child2|
        if child1.static_suffix.nil?
          1
        elsif child2.static_suffix.nil?
          -1
        elsif child2.static_suffix.end_with?(child1.static_suffix)
          1
        elsif child1.static_suffix.end_with?(child2.static_suffix)
          -1
        else
          0
        end
      end

      parametric_child
    end

    def create_wildcard_child
      @wildcard_child ||= WildcardNode.new
    end

    def split(parent_node, length)
      parent_prefix = @prefix[0, length]
      child_prefix = @prefix[length, @prefix.length - length]

      @prefix = child_prefix
      compile_prefix_match

      static_node = StaticNode.new(parent_prefix)
      static_node.static_children[child_prefix[0]] = self
      parent_node.static_children[parent_prefix[0]] = static_node

      static_node
    end

    def get_next_node(path, path_index, node_stack, params_count)
      node = find_static_matching_child(path, path_index)
      parametric_brother_node_index = 0

      unless node
        return @wildcard_child if @parametric_children.empty?

        node = @parametric_children[0]
        parametric_brother_node_index = 1
      end

      if @wildcard_child
        node_stack << {
          params_count: params_count,
          brother_path_index: path_index,
          brother_node: @wildcard_child
        }
      end

      i = @parametric_children.length - 1
      while i >= parametric_brother_node_index
        node_stack << {
          params_count: params_count,
          brother_path_index: path_index,
          brother_node: @parametric_children[i]
        }
        i -= 1
      end

      node
    end

    private

    def compile_prefix_match
      if @prefix.length == 1
        @match_prefix = ->(_, _) { true }
        return
      end

      lines = (1...@prefix.length).map do |i|
        "path[i + #{i}]&.ord == #{@prefix[i].ord}"
      end

      @match_prefix = eval("->(path, i) { #{lines.join(" && ")} }")
    end
  end

  class ParametricNode < ParentNode
    attr_reader :static_suffix, :node_paths

    def initialize(static_suffix, node_path)
      super()
      @static_suffix = static_suffix
      @kind = Node::PARAMETRIC

      @node_paths = Set.new([node_path])
    end

    def get_next_node(path, path_index, _, _)
      find_static_matching_child(path, path_index)
    end
  end

  class WildcardNode < Node
    def initialize
      super
      @kind = Node::WILDCARD
    end

    def get_next_node(*)
      nil
    end
  end
end

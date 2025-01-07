# frozen_string_literal: true

##
# Represents a tree of method nodes. The tree consists of:
#
# * a root node;
# * method nodes, each of which represents an action in a controller;
# * parent nodes attached to one or several method nodes;
#
# A method node together with its parent nodes represent a complete inheritance chain.
#
#                                                 Nodes::Root
#                                                      |
#                                     Nodes::Parent<ApplicationController>
#                                                      |
#                                      Nodes::Parent<Api::BaseController>
#                                            /                        \
#             Nodes::Parent<Api::V1::UsersController>         Nodes::Parent<Api::V2::UsersController>
#                     /                     \                                     |
#            Nodes::Method<index>   Nodes::Method<show>                  Nodes::Method<show>
#
class Rage::OpenAPI::Nodes::Root
  attr_reader :leaves
  attr_accessor :version, :title

  def initialize
    @parent_nodes_cache = {}
    @leaves = []
  end

  # @return [Array<Rage::OpenAPI::Nodes::Parent>]
  def parent_nodes
    @parent_nodes_cache.values
  end

  # @param controller [RageController::API]
  # @param action [String]
  # @param parent_nodes [Array<Rage::OpenAPI::Nodes::Parent>]
  # @return [Rage::OpenAPI::Nodes::Method]
  def new_method_node(controller, action, parent_nodes)
    node = Rage::OpenAPI::Nodes::Method.new(controller, action, parent_nodes)
    @leaves << node

    node
  end

  # @param controller [RageController::API]
  # @return [Rage::OpenAPI::Nodes::Parent]
  def new_parent_node(controller)
    @parent_nodes_cache[controller] ||= begin
      node = Rage::OpenAPI::Nodes::Parent.new(self, controller)
      yield(node)
      node
    end
  end
end

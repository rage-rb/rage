# frozen_string_literal: true

class Rage::OpenAPI::Nodes::Parent
  attr_reader :root, :controller
  attr_accessor :deprecated, :private, :auth, :responses

  def initialize(root, controller)
    @root = root
    @controller = controller

    @auth = []
    @responses = {}
  end
end

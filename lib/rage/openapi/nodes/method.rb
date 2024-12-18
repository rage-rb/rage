# frozen_string_literal: true

class Rage::OpenAPI::Nodes::Method
  attr_reader :controller, :action, :parents
  attr_accessor :http_method, :http_path, :summary, :tag, :deprecated, :private, :description,
    :request, :responses, :parameters

  def initialize(controller, action, parents)
    @controller = controller
    @action = action
    @parents = parents

    @responses = {}
    @parameters = []
  end

  def root
    @parents[0].root
  end

  def auth
    @parents.flat_map(&:auth)
  end
end

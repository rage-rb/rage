# frozen_string_literal: true

module ControllerHelper
  def run_action(controller, action)
    handler = controller.__register_action(action)
    env, params = {}, nil

    controller.new(env, params).public_send(handler)
  end
end

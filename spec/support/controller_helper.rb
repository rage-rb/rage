# frozen_string_literal: true

module ControllerHelper
  def run_action(controller, action, params: {}, env: {})
    handler = controller.__register_action(action)
    controller.new(env, params).public_send(handler)
  end
end

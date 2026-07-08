# frozen_string_literal: true

RSpec.shared_context "mocked_rage_routes" do
  before do
    # Keep builder specs stable regardless of the local checkout directory name.
    allow(Rage).to receive(:root).and_return(Rage.root.class.new("/tmp/rage"))

    allow(Rage.__router).to receive(:routes) do
      routes.map do |method_path_component, controller_action_component|
        method, path = method_path_component.split(" ", 2)
        controller, action = controller_action_component.split("#", 2)

        {
          method:,
          path:,
          meta: { controller_class: Object.const_get(controller), action: }
        }
      end
    end
  end
end

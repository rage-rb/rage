# frozen_string_literal: true

require "rage/all"
require_relative "support/integration_helper"
require_relative "support/request_helper"
require_relative "support/controller_helper"
require_relative "support/reactor_helper"
require_relative "support/websocket_helper"
require_relative "support/contexts/mocked_classes"
require_relative "support/contexts/mocked_rage_routes"

RSpec.configure do |config|

  # Uncomment the line below to enable focused mode
  config.filter_run focus: true

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    Iodine.patch_rack
  end

  config.include IntegrationHelper
  config.include RequestHelper
  config.include ControllerHelper
  config.include ReactorHelper
  config.include WebSocketHelper

  config.include_context "mocked_classes", include_shared: true
  config.include_context "mocked_rage_routes", include_shared: true
end

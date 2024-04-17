Iodine.patch_rack

require_relative "#{Rage.root}/config/environments/#{Rage.env}"

# Run application initializers
Dir["#{Rage.root}/config/initializers/**/*.rb"].each { |initializer| load(initializer) }

# Load application classes
Rage.code_loader.setup

require_relative "#{Rage.root}/config/routes"

require "rage/ext/setup"

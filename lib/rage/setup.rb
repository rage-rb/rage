Iodine.patch_rack

begin
  require_relative "#{Rage.root}/config/environments/#{Rage.env}"
rescue LoadError
  raise LoadError, "The <#{Rage.env}> environment could not be found. Please check the environment name."
end

# Run application initializers
Dir["#{Rage.root}/config/initializers/**/*.rb"].each { |initializer| load(initializer) }

require "rage/ext/setup"

# Load application classes
Rage.code_loader.setup

require_relative "#{Rage.root}/config/routes"

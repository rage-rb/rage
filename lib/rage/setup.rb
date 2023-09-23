Iodine.patch_rack

project_root = Pathname.new(".").expand_path

require_relative "#{project_root}/config/environments/#{Rage.env}"
Dir["#{project_root}/app/**/*.rb"].each { |path| require_relative path }
require_relative "#{project_root}/config/routes"

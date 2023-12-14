Iodine.patch_rack

require_relative "#{Rage.root}/config/environments/#{Rage.env}"

# Run application initializers
Dir["#{Rage.root}/config/initializers/**/*.rb"].each do |initializer|
  load(initializer)
end

# Load application classes
autoload_path = "#{Rage.root}/app/"
# TODO: prettify with methods .development? / .production?
enable_reloading = Rage.env == 'development'
enable_eager_loading = Rage.env == 'production'

loader = Rage.code_loader
loader.push_dir(autoload_path)
# The first level of directories in app directory won't be treated as modules
# e.g. app/controllers/pages_controller.rb will be linked to PagesController class
# instead of Controllers::PagesController
loader.collapse("#{Rage.root}/app/*")
loader.enable_reloading if enable_reloading
loader.setup
loader.eager_load if enable_eager_loading

require_relative "#{Rage.root}/config/routes"

Iodine.patch_rack

require_relative "#{Rage.root}/config/environments/#{Rage.env}"

# TODO: add initializers
autoload_path = "#{Rage.root}/app/"
# TODO: prettify with methods .development? / .production?
enable_reloading = Rage.env == 'development'
enable_eager_loading = Rage.env == 'production'

require 'zeitwerk'
loader = Zeitwerk::Loader.new
loader.push_dir(autoload_path)
# The first level of directories in app directory won't be treated as modules
# e.g. app/controllers/pages_controller.rb will be linked to PagesController class
# instead of Controllers::PagesController
loader.collapse("#{Rage.root}/app/*")
loader.enable_reloading if enable_reloading
loader.setup

loader.eager_load if enable_eager_loading

if enable_reloading
  require 'filewatcher'
  file_watcher = Filewatcher.new(autoload_path)

  Thread.new do
    file_watcher.watch do
      loader.reload
      Rage.__router.reset_routes
      load("#{Rage.root}/config/routes.rb")
    end
  end
end

require_relative "#{Rage.root}/config/routes"

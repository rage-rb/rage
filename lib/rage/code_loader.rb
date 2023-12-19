# frozen_string_literal: true

require "zeitwerk"

class Rage::CodeLoader
  def initialize
    @loader = Zeitwerk::Loader.new
    @reloading = false
  end

  def setup
    autoload_path = "#{Rage.root}/app"
    enable_reloading = Rage.env.development?
    enable_eager_loading = !Rage.env.development? && !Rage.env.test?

    @loader.push_dir(autoload_path)
    # The first level of directories in app directory won't be treated as modules
    # e.g. app/controllers/pages_controller.rb will be linked to PagesController class
    # instead of Controllers::PagesController
    @loader.collapse("#{Rage.root}/app/*")
    @loader.enable_reloading if enable_reloading
    @loader.setup
    @loader.eager_load if enable_eager_loading
  end

  def reload
    @reloading = true
    @loader.reload
    Rage.__router.reset_routes
    load("#{Rage.root}/config/routes.rb")
  end

  def reloading?
    @reloading
  end
end

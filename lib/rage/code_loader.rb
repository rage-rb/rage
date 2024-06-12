# frozen_string_literal: true

require "zeitwerk"

class Rage::CodeLoader
  def initialize
    @reloading = false
  end

  def setup
    @loader = Zeitwerk::Loader.new

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

  # in standalone mode - reload the code and the routes
  def reload
    return unless @loader

    @reloading = true
    @loader.reload

    Rage.__router.reset_routes
    load("#{Rage.root}/config/routes.rb")

    unless Rage.autoload?(:Cable) # the `Cable` component is loaded
      Rage::Cable.__router.reset
    end
  end

  # in Rails mode - reset the routes; everything else will be done by Rails
  def rails_mode_reload
    return if @loader

    @reloading = true
    Rage.__router.reset_routes
  end

  def reloading?
    @reloading
  end
end

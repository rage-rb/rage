# frozen_string_literal: true

require "zeitwerk"

class Rage::CodeLoader
  def initialize
    @reloading = false
    @autoload_path = Rage.root.join("app")
  end

  def setup
    @loader = Zeitwerk::Loader.new

    enable_reloading = Rage.env.development?
    enable_eager_loading = !Rage.env.development? && !Rage.env.test?

    @loader.push_dir(@autoload_path.to_s)
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

    unless Rage.autoload?(:OpenAPI) # the `OpenAPI` component is loaded
      Rage::OpenAPI.__reset_data_cache
    end
  end

  # in Rails mode - reset the routes; everything else will be done by Rails
  def rails_mode_reload
    return if @loader

    @reloading = true
    Rage.__router.reset_routes

    unless Rage.autoload?(:Cable) # the `Cable` component is loaded
      Rage::Cable.__router.reset
    end

    unless Rage.autoload?(:OpenAPI) # the `OpenAPI` component is loaded
      Rage::OpenAPI.__reset_data_cache
    end
  end

  def reloading?
    @reloading
  end

  def check_updated!
    current_watched = @autoload_path.glob("**/*.rb") + Rage.root.glob("config/routes.rb")
    current_update_at = current_watched.max_by { |path| path.exist? ? path.mtime.to_f : 0 }&.mtime.to_f
    return false if !@last_watched && !@last_update_at

    current_watched.size != @last_watched.size || current_update_at != @last_update_at

  ensure
    @last_watched, @last_update_at = current_watched, current_update_at
  end
end

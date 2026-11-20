# frozen_string_literal: true

require "zeitwerk"

class Rage::CodeLoader
  BACKGROUND_RELOAD_INTERVAL = 1_000
  private_constant :BACKGROUND_RELOAD_INTERVAL

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

    configure_components
  end

  # in standalone mode - reload the code and the routes
  def reload
    return unless @loader

    @reloading = true
    @reload_in_progress = true
    @loader.reload

    Rage.__router.reset_routes
    load("#{Rage.root}/config/routes.rb")

    reload_components
    Rage.config.run_hooks_for(:after_reload)
  ensure
    @reload_in_progress = false
  end

  # @private
  # Development only. Reload the code when the watched files change, even if the server receives no requests.
  # If a background reload fails, the request-time change tracking is left as is so that the next request retries the reload and renders the error.
  # @yieldreturn [Array<String>] the files to watch
  def reload_in_background(&watched_files)
    return unless @loader

    snapshot = -> { watched_files.call.to_h { |file| [file, File.exist?(file) ? File.mtime(file) : nil] } }
    last_snapshot = snapshot.call

    Iodine.run_every(BACKGROUND_RELOAD_INTERVAL) do
      next if @reload_in_progress

      current_snapshot = snapshot.call
      next if current_snapshot == last_snapshot

      last_snapshot = current_snapshot
      reload
      # the whole application has been reloaded - sync the request-time change tracking
      check_updated!
      # the reload could change the list of watched files, e.g. if a daemon's parent class changed
      last_snapshot = snapshot.call
    rescue ScriptError, StandardError => e
      Rage.logger.error("Failed to reload code: #{e.class} (#{e.message})")
    end
  end

  # @private
  # Whether the constant is managed by the code loader and will be reloaded.
  # @return [Boolean, nil] `nil` if the code loader is not set up (e.g. in Rails mode)
  def reloadable?(cpath)
    @loader&.unloadable_cpath?(cpath)
  end

  # in Rails mode - reset the routes; everything else will be done by Rails
  def rails_mode_reload
    return if @loader

    @reloading = true
    Rage.__router.reset_routes

    reload_components
    Rage.config.run_hooks_for(:after_reload)
  end

  def reloading?
    @reloading
  end

  def check_updated!
    current_watched = @autoload_path.glob("**/*.{rb,erb}") + Rage.root.glob("config/routes.rb") + Rage.root.glob("config/openapi_components.*")
    current_watched += Rage.config.code_loader.reload_paths.flat_map { |pattern| Rage.root.glob(pattern) }

    current_update_at = current_watched.max_by { |path| path.exist? ? path.mtime.to_f : 0 }&.mtime.to_f
    return false if !@last_watched && !@last_update_at

    current_watched.size != @last_watched.size || current_update_at != @last_update_at

  ensure
    @last_watched, @last_update_at = current_watched, current_update_at
  end

  def load_file(path)
    @loader.load_file(path)
  end

  private

  def configure_components
    if Rage.env.development? && (Rage.config.deferred.configured? || Rage.config.deferred.has_default_disk_storage?)
      # if there's at least one task, `Rage::Deferred` will be automatically loaded in production;
      # in development, however, eager loading is disabled, and we want to automatically load
      # the module in case it was explicitly configured or if a disk storage exists
      Rage::Deferred
    end
  end

  def reload_components
    unless Rage.autoload?(:Cable) # the `Cable` component is loaded
      ObjectSpace.each_object(Rage::Cable::Router).each(&:reset)
    end

    unless Rage.autoload?(:OpenAPI) # the `OpenAPI` component is loaded
      Rage::OpenAPI.__reset_data_cache
    end

    unless Rage.autoload?(:Events) # the `Events` component is loaded
      Rage::Events.__reset_subscribers
    end
  end
end

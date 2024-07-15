##
# Support legacy URL helpers that use hashes instead of the `:to` keyword argument.
#
# @example
#   get "/photos/:id" => "photos#show"
# @example
#   mount Sidekiq::Web => "/sidekiq"
# @example
#   get "search" => :index
# @example
#   get "admin_users" => "users"
module Rage::Router::DSLPlugins::LegacyHashNotation
  %i(get post put patch delete).each do |action_name|
    define_method(action_name) do |*args, **kwargs|
      if args.empty? && !kwargs.empty?
        path, handler = kwargs.first

        to = if handler.is_a?(Symbol)
          raise ArgumentError, "Could not derive the controller value from the route definitions" if @controllers.empty?
          "#{@controllers.last}##{handler}"
        elsif handler.is_a?(String) && !handler.include?("#")
          "#{handler}##{path.split("/").last}"
        elsif handler.is_a?(String)
          handler
        end
      end

      if path && to
        options = kwargs.except(path).merge(to: to)
        super(path, **options)
      else
        super(*args, **kwargs)
      end
    end
  end

  def mount(*args, **kwargs)
    if args.empty? && !kwargs.empty?
      app, at = kwargs.first
      options = kwargs.except(app).merge(at: at)
      super(app, **options)
    else
      super(*args, **kwargs)
    end
  end
end

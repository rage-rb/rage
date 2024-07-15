##
# Support the `:controller` and `:action` options.
#
# @example
#   get :admins, controller: :users
# @example
#   post :search, action: :index
module Rage::Router::DSLPlugins::ControllerActionOptions
  %i(get post put patch delete).each do |action_name|
    define_method(action_name) do |*args, **kwargs|
      if args.length == 1 && !kwargs.has_key?(:to) && (kwargs.has_key?(:controller) || kwargs.has_key?(:action))
        path = args[0]
        controller = kwargs.delete(:controller) || @controllers.last || raise(ArgumentError, "Could not derive the controller value from the route definitions")
        action = kwargs.delete(:action) || path.split("/").last
      end

      if controller && action
        kwargs[:to] = "#{controller}##{action}"
        super(path, **kwargs)
      else
        super(*args, **kwargs)
      end
    end
  end
end

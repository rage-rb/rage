##
# Support the `as` option. As Rage currently doesn't generate named route helpers, we simply ignore it.
#
# @example
#   get "/photos/:id", to: "photos#show", as: :user_photos
module Rage::Router::DSLPlugins::NamedRouteHelpers
  %i(get post put patch delete).each do |action_name|
    define_method(action_name) do |*args, **kwargs|
      kwargs.delete(:as)
      super(*args, **kwargs)
    end
  end
end

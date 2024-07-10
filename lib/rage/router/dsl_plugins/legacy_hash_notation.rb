##
# Support legacy URL helpers that use hashes instead of the `:to` keyword argument.
#
# @example
#   get "/photos/:id" => "photos#show"
module Rage::Router::DSLPlugins::LegacyHashNotation
  %i(get post put patch delete).each do |action_name|
    define_method(action_name) do |*args|
      if (arg = args[0]).is_a?(Hash)
        # get "/photos/:id" => "photos#show"
        path, controller = arg.first
        options = arg.except(path).merge(to: controller)
      else
        # get "/photos/:id", to: "photos#show"
        path, options = args
        options ||= {} # in case it's just `get "photos"`
      end

      super(path, **options)
    end
  end
end

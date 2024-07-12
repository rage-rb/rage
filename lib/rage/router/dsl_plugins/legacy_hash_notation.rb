##
# Support legacy URL helpers that use hashes instead of the `:to` keyword argument.
#
# @example
#   get "/photos/:id" => "photos#show"
module Rage::Router::DSLPlugins::LegacyHashNotation
  %i(get post put patch delete).each do |action_name|
    define_method(action_name) do |*args, **kwargs|
      if args.empty? && !kwargs.empty?
        path, to = kwargs.first
        options = kwargs.except(path).merge(to: to)
        super(path, **options)
      else
        super(*args, **kwargs)
      end
    end
  end
end

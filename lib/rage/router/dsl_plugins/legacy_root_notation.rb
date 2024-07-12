##
# Support legacy root helpers that don't use the `:to` keyword argument.
#
# @example
#   root "photos#index"
module Rage::Router::DSLPlugins::LegacyRootNotation
  def root(*args, **kwargs)
    if args.length == 1 && args[0].is_a?(String) && kwargs.empty?
      super(to: args[0])
    else
      super(*args, **kwargs)
    end
  end
end

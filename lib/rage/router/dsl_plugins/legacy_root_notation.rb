##
# Support legacy root helpers that don't use the `:to` keyword argument.
#
# @example
#   root "photos#index"
module Rage::Router::DSLPlugins::LegacyRootNotation
  def root(arg)
    if arg.is_a?(String)
      # root "photos#index"
      super(to: arg)
    else
      # root to: "photos#index"
      super(**arg)
    end
  end
end

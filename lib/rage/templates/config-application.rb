require "bundler/setup"
Bundler.require(*Rage.groups)

require "rage/all"

Rage.configure do
  # use this to add settings that are constant across all environments
end

require "rage/setup"

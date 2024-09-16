require "bundler/setup"
require "rage"
Bundler.require(*Rage.groups)

<% if @use_database -%>
require "active_record"
<% end -%>
require "rage/all"

Rage.configure do
  # use this to add settings that are constant across all environments
end

require "rage/setup"

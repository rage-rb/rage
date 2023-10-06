Iodine.patch_rack

require_relative "#{Rage.root}/config/environments/#{Rage.env}"


# load application files
app, bad = Dir["#{Rage.root}/app/**/*.rb"], []

loop do
  path = app.shift
  break if path.nil?

  require_relative path

# push the file to the end of the list in case it depends on another file that has not yet been required;
# re-raise if only errored out files are left
rescue NameError
  raise if (app - bad).empty?
  app << path
  bad << path
end

require_relative "#{Rage.root}/config/routes"

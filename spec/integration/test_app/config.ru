require_relative "config/application"

run Rage.application

map "/cable" do
  run Rage.cable.application
end

map "/publicapi" do
  run Rage.openapi.application
end

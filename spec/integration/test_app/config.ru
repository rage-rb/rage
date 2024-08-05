require_relative "config/application"

run Rage.application

map "/cable" do
  run Rage.cable.application
end

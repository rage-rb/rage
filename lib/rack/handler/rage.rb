require "rage"
Rack::Handler.register("rage", "Rage::Handler") if defined?(Rack::Handler)

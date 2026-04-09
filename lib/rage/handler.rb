module Rage
  module Handler
    def self.run(app, options = {})
      Rage::CLI.new([], {
        port: options[:Port],
        binding: options[:Host],
        environment: options[:environment]
      }).server
    end
  end
end

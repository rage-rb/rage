module Rage
  module Handler
    def self.run(app, options = {})
      Rage.application = app

      cli_options = {}
      cli_options[:port] = options[:Port] if options[:Port]
      cli_options[:binding] = options[:Host] if options[:Host]
      cli_options[:environment] = options[:environment] if options[:environment]
      cli_options[:quiet] = options[:quiet] if options[:quiet]

      Rage::CLI.new([], cli_options).server(app: app)
    end
  end
end

# frozen_string_literal: true

require "thor"
require "rack"

module Rage
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "new PATH", "Create a new application."
    def new(path)
      require "rage/all"
      NewAppGenerator.start([path])
    end

    desc "s", "Start the app server."
    option :port, aliases: "-p", desc: "Runs Rage on the specified port - defaults to 3000."
    option :environment, aliases: "-e", desc: "Specifies the environment to run this server under (test/development/production)."
    option :binding, aliases: "-b", desc: "Binds Rails to the specified IP - defaults to 'localhost' in development and '0.0.0.0' in other environments."
    option :config, aliases: "-c", desc: "Uses a custom rack configuration."
    option :help, aliases: "-h", desc: "Show this message."
    def server
      return help("server") if options.help?

      set_env(options)

      app = ::Rack::Builder.parse_file(options[:config] || "config.ru")
      app = app[0] if app.is_a?(Array)

      port = options[:port] || Rage.config.server.port
      address = options[:binding] || (Rage.env.production? ? "0.0.0.0" : "localhost")
      timeout = Rage.config.server.timeout
      max_clients = Rage.config.server.max_clients

      ::Iodine.listen service: :http, handler: app, port: port, address: address, timeout: timeout, max_clients: max_clients
      ::Iodine.threads = Rage.config.server.threads_count
      ::Iodine.workers = Rage.config.server.workers_count

      ::Iodine.start
    end

    desc "routes", "List all routes."
    option :grep, aliases: "-g", desc: "Filter routes by pattern"
    option :help, aliases: "-h", desc: "Show this message."
    def routes
      return help("routes") if options.help?
      # the result would be something like this:
      # Verb  Path  Controller#Action
      # GET   /     application#index

      # load config/application.rb
      set_env(options)
      environment

      routes = Rage.__router.routes
      pattern = options[:grep]
      routes.unshift({ method: "Verb", path: "Path", meta: { raw_handler: "Controller#Action" } })

      grouped_routes = routes.each_with_object({}) do |route, memo|
        if pattern && !memo.empty?
          next unless route[:path].match?(pattern) || route[:meta][:raw_handler].to_s.match?(pattern) || route[:method].match?(pattern)
        end

        key = [route[:path], route[:meta][:raw_handler]]

        if route[:meta][:mount]
          memo[key] = route.merge(method: "") unless route[:path].end_with?("*")
          next
        end

        if memo[key]
          memo[key][:method] += "|#{route[:method]}"
        else
          memo[key] = route
        end
      end

      longest_path = longest_method = 0
      grouped_routes.each do |_, route|
        longest_path = route[:path].length if route[:path].length > longest_path
        longest_method = route[:method].length if route[:method].length > longest_method
      end

      margin = 3
      longest_path += margin
      longest_method += margin

      grouped_routes.each_with_index do |(_, route), i|
        meta = route[:constraints]
        meta.merge!(route[:defaults]) if route[:defaults]

        handler = route[:meta][:raw_handler]
        handler = "#{handler} #{meta}" unless meta&.empty?

        puts format("%-#{longest_method}s%-#{longest_path}s%s", route[:method], route[:path], handler)
        puts "\n" if i == 0
      end
    end

    desc "c", "Start the app console."
    option :help, aliases: "-h", desc: "Show this message."
    def console
      return help("console") if options.help?

      set_env(options)

      require "irb"
      environment
      ARGV.clear
      IRB.start
    end

    private

    def environment
      require File.expand_path("config/application.rb", Dir.pwd)

      if Rage.config.internal.rails_mode
        require File.expand_path("config/environment.rb", Dir.pwd)
      end
    end

    def set_env(options)
      ENV["RAGE_ENV"] = options[:environment] if options[:environment]
    end
  end

  class NewAppGenerator < Thor::Group
    include Thor::Actions
    argument :path, type: :string

    def self.source_root
      File.expand_path("templates", __dir__)
    end

    def create_directory
      empty_directory(path)
    end

    def copy_files
      Dir.glob("*", base: self.class.source_root).each do |template|
        *template_path_parts, template_name = template.split("-")
        template(template, "#{path}/#{template_path_parts.join("/")}/#{template_name}")
      end
    end
  end
end

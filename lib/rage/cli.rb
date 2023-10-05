# frozen_string_literal: true

require "thor"
require "rage"

module Rage
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "new PATH", "Create a new application."
    def new(path)
      NewAppGenerator.start([path])
    end

    desc "s", "Start the app server."
    def server
      app = ::Rack::Builder.parse_file("config.ru")
      app = app[0] if app.is_a?(Array)

      ::Iodine.listen service: :http, handler: app, port: Rage.config.port
      ::Iodine.threads = Rage.config.threads_count
      ::Iodine.workers = Rage.config.workers_count

      ::Iodine.start
    end

    desc 'routes', 'List all routes.'
    def routes
      # the result would be something like this:
      # +----------------------+----------------------+----------------------+
      # | Action               | Verb                 | Path                 | Controller#Action
      # | index                | GET                  | /                    | application#index

      # load config/application.rb
      require File.expand_path('config/application.rb', Dir.pwd)
      # load config/routes.rb
      require File.expand_path('config/routes.rb', Dir.pwd)

      routes = Rage.routes.router.routes

      # construct a table
      table = [['+---------------------------', '+---------------------------', '+---------------------------+']]

      table << ['| Action'.ljust(20), '| Verb'.ljust(20), '| Path'.ljust(20), "| Controller#Action\n\n"]

      routes.each do |route|
        table << [
          route[:raw_handler].split('#').last.ljust(20),
          route[:method].ljust(20),
          route[:path].ljust(20),
          route[:raw_handler].ljust(20)
        ]
      end
      # print the table
      table.each do |row|
        # this should be changed to use the main logger when added
        puts row.join
      end
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

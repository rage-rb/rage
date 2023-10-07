# frozen_string_literal: true
require "thor"
require "rage"
require "irb"

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
    option :grep, aliases: "-g", desc: "Filter routes by pattern"
    def routes
      # the result would be something like this:
      # Action    Verb  Path  Controller#Action
      # index     GET   /     application#index

      # load config/application.rb
      require_file_by_path('config/application.rb')

      routes = Rage.__router.routes

      pattern = options[:grep]

      if pattern
        routes = routes.select do |route|
          route[:path].match?(pattern) || route[:raw_handler].to_s.match?(pattern) || route[:method].match?(pattern)
        end
      end

      return puts 'Action    Verb  Path  Controller#Action' if routes.empty?
  
      # construct a table
      table = []

      # longest_path is either the length of the longest path or 5
      longest_path = routes.map { |route| route[:path].length }.max + 3
      longest_path = longest_path > 5 ? longest_path : 5

      longest_verb = routes.map { |route| route[:method].length }.max + 3
      longest_verb = longest_verb > 4 ? longest_verb : 7

      # longest_handler is either the length of the longest handler or 7, since DELETE is the longest HTTP method
      longest_handler = routes.map { |route| route[:raw_handler].is_a?(Proc) ? 7 : route[:raw_handler].split('#').last.length }.max + 3
      longest_handler = longest_handler > 7 ? longest_handler : 7

      # longest_controller is either the length of the longest controller or 12, since Controller#{length} is the longest controller
      longest_controller = routes.map { |route| route[:raw_handler].is_a?(Proc) ? 7 : route[:raw_handler].to_s.length }.max + 3
      longest_controller = longest_controller > 12 ? longest_controller : 12

      routes.each do |route|
        table << [
          format("%- #{longest_handler}s", route[:raw_handler].is_a?(Proc) ? 'Lambda' : route[:raw_handler].split('#').last),
          format("%- #{longest_verb}s", route[:method]),
          format("%- #{longest_path}s", route[:path]),
          format("%- #{longest_controller}s", route[:raw_handler].is_a?(Proc) ? 'Lambda' : route[:raw_handler])
        ]
      end

      table.unshift([format("%- #{longest_handler}s", 'Action'), format("%- #{longest_verb}s", 'Verb'), format("%- #{longest_path}s", 'Path'),
                     format("%- #{longest_path}s", "Controller#Action\n")])
      # print the table
      table.each do |row|
        # this should be changed to use the main logger when added
        puts row.join
      end
    end

    desc "c", "Start the app console."
    def console
      ARGV.clear
      IRB.start
    end

    private

    def require_file_by_path(file)
      require File.expand_path(file, Dir.pwd)
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
      Dir.glob(%w(* .irbrc), base: self.class.source_root).each do |template|
        *template_path_parts, template_name = template.split("-")
        template(template, "#{path}/#{template_path_parts.join("/")}/#{template_name}")
      end
    end
  end
end

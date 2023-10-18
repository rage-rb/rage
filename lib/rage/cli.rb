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
      # Verb  Path  Controller#Action
      # GET   /     application#index

      # load config/application.rb
      environment

      routes = Rage.__router.routes
      pattern = options[:grep]
      routes.unshift({ method: "Verb", path: "Path", raw_handler: "Controller#Action" })

      grouped_routes = routes.each_with_object({}) do |route, memo|
        if pattern && !memo.empty?
          next unless route[:path].match?(pattern) || route[:raw_handler].to_s.match?(pattern) || route[:method].match?(pattern)
        end

        key = [route[:path], route[:raw_handler]]
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

        handler = route[:raw_handler]
        handler = "#{handler} #{meta}" unless meta&.empty?

        puts format("%-#{longest_method}s%-#{longest_path}s%s", route[:method], route[:path], handler)
        puts "\n" if i == 0
      end
    end

    desc "c", "Start the app console."
    def console
      environment
      ARGV.clear
      IRB.start
    end

    private

    def environment
      require File.expand_path("config/application.rb", Dir.pwd)
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

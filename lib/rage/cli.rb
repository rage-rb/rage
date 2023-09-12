# frozen_string_literal: true

require "thor"
require "iodine"
require "rack"

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

      ::Iodine.listen service: :http, handler: app
      ::Iodine.threads = 1
      ::Iodine.start
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

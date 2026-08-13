# frozen_string_literal: true

module Rage::CLI
  class NewAppGenerator < Thor::Group
    include Thor::Actions
    argument :path, type: :string
    argument :database, type: :string, required: false

    def self.source_root
      File.expand_path("../templates", __dir__)
    end

    def setup
      @use_database = !database.nil?
    end

    def create_directory
      empty_directory(path)
    end

    def copy_files
      inject_templates
    end

    def install_database
      return unless @use_database

      @app_name = path.tr("-", "_").downcase
      append_to_file "#{path}/Gemfile", <<~RUBY

        gem "#{get_db_gem_name}"
        gem "activerecord"
        gem "standalone_migrations", require: false
      RUBY

      inject_templates("db-templates")
      inject_templates("db-templates/#{database}")
    end

    private

    def inject_templates(from = nil)
      root = "#{self.class.source_root}/#{from}"

      Dir.glob("*", base: root).each do |template|
        next if File.directory?("#{root}/#{template}")

        *template_path_parts, template_name = template.split("-")
        template("#{root}/#{template}", [path, *template_path_parts, template_name].join("/"))
      end
    end

    def get_db_gem_name
      case database
      when "mysql"
        "mysql2"
      when "trilogy"
        "trilogy"
      when "postgresql"
        "pg"
      when "sqlite3"
        "sqlite3"
      end
    end
  end
end

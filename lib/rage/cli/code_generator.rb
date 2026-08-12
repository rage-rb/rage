# frozen_string_literal: true

module Rage::CLI
  class CodeGenerator < Base
    include Thor::Actions

    def self.source_root
      File.expand_path("../templates", __dir__)
    end

    desc "migration NAME", "Generate a new migration"
    def migration(name = nil)
      return help("migration") if name.nil?

      setup
      Rake::Task["db:new_migration"].invoke(name)
    end

    desc "model NAME", "Generate a new model"
    def model(name = nil)
      return help("model") if name.nil?

      setup
      migration("create_#{name.pluralize}")
      @model_name = name.classify
      template("model-template/model.rb", "app/models/#{name.singularize.underscore}.rb")
    end

    desc "controller NAME", "Generate a new controller"
    def controller(name = nil)
      return help("controller") if name.nil?

      setup
      unless defined?(ActiveSupport::Inflector)
        raise LoadError, <<~ERR
          ActiveSupport::Inflector is required to run this command. Add the following line to your Gemfile:
          gem "activesupport", require: "active_support/inflector"
        ERR
      end

      # remove trailing Controller if already present
      normalized_name = name.sub(/_?controller$/i, "")
      @controller_name = "#{normalized_name.camelize}Controller"
      file_name = "#{normalized_name.underscore}_controller.rb"

      template("controller-template/controller.rb", "app/controllers/#{file_name}")
    end

    private

    def setup
      @setup ||= begin
        require "rake"
        load "Rakefile"
      end
    end
  end
end

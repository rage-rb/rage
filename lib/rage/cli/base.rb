# frozen_string_literal: true

module Rage::CLI
  class Base < Thor
    private

    def environment
      require File.expand_path("config/application.rb", Dir.pwd)

      if Rage.config.internal.rails_mode
        require File.expand_path("config/environment.rb", Dir.pwd)
      end
    end

    def set_env(options)
      if options[:environment]
        ENV["RAGE_ENV"] = ENV["RAILS_ENV"] = options[:environment]
      elsif ENV["RAGE_ENV"]
        ENV["RAILS_ENV"] = ENV["RAGE_ENV"]
      elsif ENV["RAILS_ENV"]
        ENV["RAGE_ENV"] = ENV["RAILS_ENV"]
      else
        ENV["RAGE_ENV"] = ENV["RAILS_ENV"] = "development"
      end
    end
  end
end

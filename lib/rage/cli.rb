# frozen_string_literal: true

require "thor"
require "rack"
require "rage/version"

module Rage
  class CLICodeGenerator < Thor
    include Thor::Actions

    def self.source_root
      File.expand_path("templates", __dir__)
    end

    desc "migration NAME", "Generate a new migration."
    def migration(name = nil)
      return help("migration") if name.nil?

      setup
      Rake::Task["db:new_migration"].invoke(name)
    end

    desc "model NAME", "Generate a new model."
    def model(name = nil)
      return help("model") if name.nil?

      setup
      migration("create_#{name.pluralize}")
      @model_name = name.classify
      template("model-template/model.rb", "app/models/#{name.singularize.underscore}.rb")
    end

    desc "controller NAME", "Generate a new controller."
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

  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "new PATH", "Create a new application."
    option :database, aliases: "-d", desc: "Preconfigure for selected database.", enum: %w(mysql trilogy postgresql sqlite3)
    option :help, aliases: "-h", desc: "Show this message."
    def new(path = nil)
      return help("new") if options.help? || path.nil?

      require "rage/all"
      CLINewAppGenerator.start([path, options[:database]])
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

      server_options = { service: :http, handler: app }

      server_options[:port] = options[:port] || ENV["PORT"] || Rage.config.server.port
      server_options[:address] = options[:binding] || (Rage.env.production? ? "0.0.0.0" : "localhost")
      server_options[:timeout] = Rage.config.server.timeout
      server_options[:max_clients] = Rage.config.server.max_clients
      server_options[:public] = Rage.config.public_file_server.enabled ? Rage.root.join("public").to_s : nil

      ::Iodine.listen(**server_options)
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
      patch_fiber_for_irb
      ARGV.clear
      IRB.start
    end

    desc "middleware", "List Rack middleware stack enabled for the application"
    def middleware
      environment

      Rage.config.middleware.middlewares.each do |middleware|
        say "use #{middleware.first.name}"
      end
    end

    desc "version", "Return the current version of the framework"
    def version
      puts Rage::VERSION
    end

    map "generate" => :g
    desc "g TYPE", "Generate new code."
    subcommand "g", CLICodeGenerator

    map "--tasks" => :tasks
    desc "--tasks", "See the list of available tasks."
    def tasks
      require "io/console"

      tasks = linked_rake_tasks
      return if tasks.empty?

      _, max_width = IO.console.winsize
      max_task_name = tasks.max_by { |task| task.name.length }.name.length + 2
      max_comment = max_width - max_task_name - 8

      tasks.each do |task|
        comment = task.comment.length <= max_comment ? task.comment : "#{task.comment[0...max_comment - 5]}..."
        puts sprintf("rage %-#{max_task_name}s # %s", task.name, comment)
      end
    end

    def method_missing(method_name, *, &)
      set_env({})

      if respond_to?(method_name)
        Rake::Task[method_name].invoke
      else
        suggestions = linked_rake_tasks.map(&:name)
        raise UndefinedCommandError.new(method_name.to_s, suggestions, nil)
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      linked_rake_tasks.any? { |task| task.name == method_name.to_s } || super
    end

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

    def linked_rake_tasks
      require "rake"
      Rake::TaskManager.record_task_metadata = true
      load "Rakefile"

      Rake::Task.tasks.select { |task| !task.comment.nil? && task.name.start_with?("db:") }
    end

    # Override Fiber.schedule for IRB: Enforce sequential execution of fibers in the IRB environment
    def patch_fiber_for_irb
      Fiber.class_eval do
        def self.schedule(&block)
          fiber = Fiber.new(blocking: true) do
            Fiber.current.__set_id
            Fiber.current.__set_result(block.call)
          end
          fiber.resume

          fiber
        end

        def self.await(fibers)
          Array(fibers).map(&:__get_result)
        end
      end
    end
  end

  class CLINewAppGenerator < Thor::Group
    include Thor::Actions
    argument :path, type: :string
    argument :database, type: :string, required: false

    def self.source_root
      File.expand_path("templates", __dir__)
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

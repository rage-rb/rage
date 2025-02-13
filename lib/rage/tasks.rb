begin
  require "standalone_migrations"
rescue LoadError
end

class Rage::Tasks
  class << self
    def init
      load_db_tasks if defined?(StandaloneMigrations)
      load_app_tasks
    end

    private

    def load_db_tasks
      StandaloneMigrations::Configurator.prepend(Module.new do
        def configuration_file
          @path ||= begin
            @__tempfile = Tempfile.new
            @__tempfile.write <<~YAML
              config:
                database: config/database.yml
            YAML
            @__tempfile.close

            @__tempfile.path
          end
        end
      end)

      StandaloneMigrations::Tasks.load_tasks
    end

    def load_app_tasks
      Dir[Rage.root.join("lib/tasks/**/*.rake")].each { |file| load file }
    end
  end
end

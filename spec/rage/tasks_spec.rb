# frozen_string_literal: true

require "rake"
require "rage/tasks"

RSpec.describe Rage::Tasks do
  # `Rake.application` is a process-wide singleton owning the task registry; a fresh one per example
  # keeps the registry empty and tasks re-invokable, while restoring it avoids leaking into other specs.
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original_application
  end

  describe ".load_rage_tasks" do
    it "loads the openapi:validate task" do
      expect(Rake::Task.task_defined?("openapi:validate")).to eq(false)

      described_class.send(:load_rage_tasks)

      expect(Rake::Task.task_defined?("openapi:validate")).to eq(true)
    end
  end
end

RSpec.describe "openapi:validate" do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    Rage::Tasks.send(:load_rage_tasks)
    example.run
  ensure
    Rake.application = original_application
  end

  before do
    allow(Rage.config.internal).to receive(:initialized?).and_return(true)
  end

  let(:routes) do
    { "GET /users" => "UsersController#index" }
  end

  # returns the `SystemExit` error the task exited with, or `nil` if it didn't exit
  def invoke_task
    Rake::Task["openapi:validate"].invoke
    nil
  rescue SystemExit => e
    e
  end

  context "when the application is not booted" do
    before do
      allow(Rage.config.internal).to receive(:initialized?).and_return(false)
    end

    it "doesn't build the spec" do
      expect(Rage::OpenAPI).not_to receive(:build)

      expect { invoke_task }.
        to output(/OpenAPI validation requires a booted application\./).to_stderr
    end

    it "exits with status 1" do
      exit_error = nil

      expect { exit_error = invoke_task }.to output.to_stderr

      expect(exit_error.status).to eq(1)
    end
  end

  context "when the spec builds without warnings" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        # @response { id: Integer, full_name: String }
        def index
        end
      RUBY
    end

    it "prints a success message" do
      expect { invoke_task }.to output(/OpenAPI validation passed without warnings\./).to_stdout
    end

    it "doesn't exit with an error" do
      allow($stdout).to receive(:puts)

      expect(invoke_task).to be_nil
    end
  end

  context "when the build produces warnings" do
    let_class("UsersController", parent: RageController::API) do
      <<~'RUBY'
        # @response UnknownResource
        def index
        end
      RUBY
    end

    it "prints the warnings and the number of failures" do
      expect { invoke_task }.
        to output(/unrecognized `@response` tag detected/).to_stdout.
        and output(/OpenAPI validation failed with 1 warning\(s\)\./).to_stderr
    end

    it "exits with status 1" do
      allow($stdout).to receive(:puts)

      exit_error = nil

      expect { exit_error = invoke_task }.to output.to_stderr

      expect(exit_error.status).to eq(1)
    end
  end
end

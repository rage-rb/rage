# frozen_string_literal: true

require "rake"
require "rage/tasks"

RSpec.describe Rage::Tasks do
  describe ".load_rage_tasks" do
    before do
      Rake.application = Rake::Application.new
    end

    it "loads the openapi:validate task" do
      expect(Rake::Task.task_defined?("openapi:validate")).to eq(false)

      described_class.send(:load_rage_tasks)

      expect(Rake::Task.task_defined?("openapi:validate")).to eq(true)
    end
  end
end

RSpec.describe "openapi:validate" do
  subject { Rake::Task["openapi:validate"].invoke }

  before do
    Rake.application = Rake::Application.new
    Rage::Tasks.send(:load_rage_tasks)
    Rage::OpenAPI.instance_variable_set(:@__warnings, [])
    allow(Rage::OpenAPI).to receive(:build)
  end

  after do
    Rage::OpenAPI.instance_variable_set(:@__warnings, nil)
  end

  it "builds the OpenAPI spec" do
    allow($stdout).to receive(:puts)

    expect(Rage::OpenAPI).to receive(:build)

    subject
  end

  context "when there are no warnings" do
    it "prints a success message" do
      expect { subject }.to output(/OpenAPI validation passed without warnings\./).to_stdout
    end

    it "does not exit with an error" do
      allow($stdout).to receive(:puts)

      expect { subject }.not_to raise_error
    end
  end

  context "when there are warnings" do
    before do
      Rage::OpenAPI.__warnings << "unrecognized tag"
    end

    it "prints a failure message" do
      expect {
        begin
          subject
        rescue SystemExit
        end
      }.to output(/OpenAPI validation failed\./).to_stdout
    end

    it "exits with status 1" do
      allow($stdout).to receive(:puts)

      expect { subject }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }
    end
  end
end

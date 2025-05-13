RSpec.describe "Setup" do
  let(:valid_env) { "development" }
  let(:invalid_env) { "develop" }
  let(:setup_file) { File.expand_path("../lib/rage/setup.rb", __dir__) }

  before do
    allow(Rage).to receive(:env).and_return(env)
    allow(Rage).to receive(:root).and_return(Pathname.new(File.expand_path("..", __dir__)))
    allow(Rage).to receive_message_chain(:code_loader, :setup).and_return(true)
    allow(Rage).to receive_message_chain(:config, :run_after_initialize!).and_return(true)
    allow(Iodine).to receive(:patch_rack).and_return(true)
  end

  context "when environment name is valid" do
    let(:env) { valid_env }

    before do
      allow_any_instance_of(Object).to receive(:require_relative).with("#{Rage.root}/config/environments/#{Rage.env}").and_return(true)
      allow_any_instance_of(Object).to receive(:require_relative).with("#{Rage.root}/config/routes").and_return(true)
    end

    it "loads the environment without error" do
      expect { load setup_file }.not_to raise_error
    end
  end

  context "when environment name is invalid" do
    let(:env) { invalid_env }

    it "raises a custom error with a meaningful message" do
      expect { load setup_file }.
        to raise_error(LoadError, "The <#{invalid_env}> environment could not be found. Please check the environment name.")
    end
  end
end

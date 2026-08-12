# frozen_string_literal: true

require "rage/cli"

RSpec.describe Rage::CLI::OpenAPI do
  include_context "mocked_classes"
  include_context "mocked_rage_routes"

  subject(:openapi_cli) { described_class.new }

  before do
    allow(openapi_cli).to receive(:environment)
    allow(openapi_cli).to receive(:set_color) { |text, *| text }
  end

  let(:routes) do
    { "GET /users" => "UsersController#index" }
  end

  describe "#validate" do
    subject(:invoke_validate) do
      openapi_cli.validate
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

        expect { invoke_validate }.to output(/OpenAPI validation requires a booted application\./).to_stderr
      end

      it "exits with status 1" do
        exit_error = nil

        expect { exit_error = invoke_validate }.to output.to_stderr

        expect(exit_error.status).to eq(1)
      end
    end

    context "when the application is booted" do
      before do
        allow(Rage.config.internal).to receive(:initialized?).and_return(true)
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
          expect(openapi_cli).to receive(:say).with(/OpenAPI validation passed without warnings\./)

          invoke_validate
        end

        it "doesn't exit with an error" do
          allow(openapi_cli).to receive(:say)

          expect(invoke_validate).to be_nil
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

        it "prints the warnings" do
          expect { invoke_validate }.to output(/unrecognized `@response` tag detected/).to_stdout
        end

        it "exits with status 1 and prints the failure count" do
          exit_error = nil

          expect { exit_error = invoke_validate }.
            to output.to_stdout.
            and output(/OpenAPI validation failed with 1 warning\(s\)\./).to_stderr

          expect(exit_error.status).to eq(1)
        end
      end
    end
  end
end

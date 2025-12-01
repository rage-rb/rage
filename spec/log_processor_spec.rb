# frozen_string_literal: true

# rubocop:disable Lint/LiteralAsCondition
RSpec.describe Rage::LogProcessor do
  describe "#init_request_logger" do
    let(:log_processor) { described_class.new }
    let(:log_context) { Thread.current[:rage_logger] }

    let(:env) { {} }
    let(:request_tag) { "test-request-id-tag" }

    let(:custom_context) { nil }
    let(:custom_tags) { nil }

    before do
      allow(Iodine::Rack::Utils).to receive(:gen_request_tag).and_return(request_tag)

      log_processor.add_custom_context(custom_context) if custom_context
      log_processor.add_custom_tags(custom_tags) if custom_tags

      log_processor.init_request_logger(env)
    end

    after do
      Thread.current[:rage_logger] = nil
    end

    it "correctly initializes static logger" do
      expect(log_context).to match({
        tags: [instance_of(String)],
        context: {},
        request_start: instance_of(Float)
      })
    end

    it "correctly initializes dynamic logger" do
      expect(log_processor.dynamic_tags).to be_nil
      expect(log_processor.dynamic_context).to be_nil
    end

    context "with custom context" do
      context "with a single hash" do
        let(:custom_context) { [{ user_id: 1234 }] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234 },
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context).to be_nil
        end
      end

      context "with multiple hashes" do
        let(:custom_context) { [{ user_id: 1234 }, { account_id: 5678 }] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234, account_id: 5678 },
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context).to be_nil
        end
      end

      context "with a single proc" do
        let(:custom_context) { [-> { { user_id: 1234 } }] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context.call).to eq({ user_id: 1234 })
        end
      end

      context "with a single proc with dynamic value" do
        let(:custom_context) { [-> { { user_id: rand } }] }

        it "correctly initializes dynamic logger" do
          values = []

          2.times do
            values << log_processor.dynamic_context.call[:user_id]
          end

          expect(values.uniq.size).to eq(2)
        end
      end

      context "with multiple procs" do
        let(:custom_context) { [-> { { user_id: 1234 } }, -> { { account_id: 5678 } }] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context.call).to eq({ user_id: 1234, account_id: 5678 })
        end
      end

      context "with both hashes and procs" do
        let(:custom_context) do
          [
            { user_id: 1234 },
            -> { { account_id: 5678 } },
            { profile_id: 999, user_role: "admin" }
          ]
        end

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234, profile_id: 999, user_role: "admin" },
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context.call).to eq({ account_id: 5678 })
        end
      end

      context "with a proc returning nil" do
        context "with one context" do
          let(:custom_context) { [-> { { account_id: 1234 } if false }] }

          it "correctly initializes dynamic logger" do
            expect(log_processor.dynamic_tags).to be_nil
            expect(log_processor.dynamic_context.call).to eq({})
          end
        end

        context "with multiple contexts" do
          let(:custom_context) do
            [
              { user_id: 1234 },
              -> { { account_id: 5678 } if false },
              -> { { profile_id: 999 } if false }
            ]
          end

          it "correctly initializes static logger" do
            expect(log_context).to match({
              tags: [instance_of(String)],
              context: { user_id: 1234 },
              request_start: instance_of(Float)
            })
          end

          it "correctly initializes dynamic logger" do
            expect(log_processor.dynamic_tags).to be_nil
            expect(log_processor.dynamic_context.call).to eq({})
          end
        end
      end

      context "with an exception in a context proc" do
        context "with one object" do
          let(:custom_context) { [-> { raise "test" }] }

          it "lets the exception bubble up" do
            expect {
              log_processor.dynamic_context.call
            }.to raise_error(RuntimeError, "test")
          end
        end

        context "with multiple objects" do
          let(:custom_context) do
            [
              { user_id: 1234 },
              -> { raise "test" }
            ]
          end

          it "correctly initializes static logger" do
            expect(log_context).to match({
              tags: [instance_of(String)],
              context: { user_id: 1234 },
              request_start: instance_of(Float)
            })
          end

          it "lets the exception bubble up" do
            expect {
              log_processor.dynamic_context.call
            }.to raise_error(RuntimeError, "test")
          end
        end
      end

      context "with a reset context" do
        let(:custom_context) do
          [
            { user_id: 1234 },
            -> { { account_id: 5678 } }
          ]
        end

        before do
          log_processor.add_custom_context([])
          log_processor.init_request_logger(env)
        end

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [instance_of(String)],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_tags).to be_nil
          expect(log_processor.dynamic_context).to be_nil
        end
      end
    end

    context "with custom tags" do
      context "with no custom tags and custom request_id" do
        let(:env) { { "rage.request_id" => "custom-test-id" } }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: ["custom-test-id"],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags).to be_nil
        end
      end

      context "with a single tag" do
        let(:custom_tags) { ["staging"] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag, "staging"],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags).to be_nil
        end
      end

      context "with multiple tags" do
        let(:custom_tags) { ["staging", "admin_api"] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag, "staging", "admin_api"],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags).to be_nil
        end
      end

      context "with a single proc" do
        let(:custom_tags) { [-> { "staging" }] }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags.call).to eq(["staging"])
        end
      end

      context "with multiple procs" do
        let(:custom_tags) do
          [-> { "staging" }, -> { "admin_api" }]
        end

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags.call).to eq(["staging", "admin_api"])
        end
      end

      context "with both string tags and procs" do
        let(:custom_tags) do
          [
            "staging",
            -> { "admin_api" },
            "v1.2.3"
          ]
        end

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag, "staging", "v1.2.3"],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags.call).to eq(["admin_api"])
        end
      end

      context "with a proc returning nil" do
        context "with one tag" do
          let(:custom_tags) { [-> { "staging" if false }] }

          it "correctly initializes static logger" do
            expect(log_context).to match({
              tags: [request_tag],
              context: {},
              request_start: instance_of(Float)
            })
          end

          it "correctly initializes dynamic logger" do
            expect(log_processor.dynamic_context).to be_nil
            expect(log_processor.dynamic_tags.call).to eq([])
          end
        end

        context "with multiple tags" do
          let(:custom_tags) do
            [
              "staging",
              -> { "admin_api" if false },
              -> { "v1.2.3" if false }
            ]
          end

          it "correctly initializes static logger" do
            expect(log_context).to match({
              tags: [request_tag, "staging"],
              context: {},
              request_start: instance_of(Float)
            })
          end

          it "correctly initializes dynamic logger" do
            expect(log_processor.dynamic_context).to be_nil
            expect(log_processor.dynamic_tags.call).to eq([])
          end
        end
      end

      context "with a proc returning array" do
        let(:custom_tags) do
          [
            -> { ["staging", "admin_api"] }
          ]
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags.call).to eq(["staging", "admin_api"])
        end
      end

      context "with custom request_id" do
        let(:custom_tags) { ["staging"] }

        let(:env) { { "rage.request_id" => "custom-test-id" } }

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: ["custom-test-id", "staging"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with an exception in a tag proc" do
        context "with one object" do
          let(:custom_tags) { [-> { raise "test" }] }

          it "lets the exception bubble up" do
            expect {
              log_processor.dynamic_tags.call
            }.to raise_error(RuntimeError, "test")
          end
        end

        context "with multiple objects" do
          let(:custom_tags) do
            [
              "staging",
              -> { raise "test" }
            ]
          end

          it "correctly initializes static logger" do
            expect(log_context).to match({
              tags: [request_tag, "staging"],
              context: {},
              request_start: instance_of(Float)
            })
          end

          it "lets the exception bubble up" do
            expect {
              log_processor.dynamic_tags.call
            }.to raise_error(RuntimeError, "test")
          end
        end
      end

      context "with reset tags" do
        let(:custom_tags) do
          [
            "staging",
            -> { "admin_api" }
          ]
        end

        before do
          log_processor.add_custom_tags([])
          log_processor.init_request_logger(env)
        end

        it "correctly initializes static logger" do
          expect(log_context).to match({
            tags: [request_tag],
            context: {},
            request_start: instance_of(Float)
          })
        end

        it "correctly initializes dynamic logger" do
          expect(log_processor.dynamic_context).to be_nil
          expect(log_processor.dynamic_tags).to be_nil
        end
      end
    end

    context "with custom context and tags" do
      let(:custom_context) { [{ user_id: 1234, account_id: 5678 }, -> { { profile_id: 999 } }] }
      let(:custom_tags) { [-> { "staging" }] }

      it "correctly initializes static logger" do
        expect(log_context).to match({
          tags: [request_tag],
          context: { user_id: 1234, account_id: 5678 },
          request_start: instance_of(Float)
        })
      end

      it "correctly initializes dynamic logger" do
        expect(log_processor.dynamic_context.call).to eq({ profile_id: 999 })
        expect(log_processor.dynamic_tags.call).to eq(["staging"])
      end
    end
  end
end
# rubocop:enable all

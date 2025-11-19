# frozen_string_literal: true

RSpec.describe Rage::LogProcessor do
  describe "#init_request_logger" do
    subject do
      log_processor.init_request_logger(env)
      Thread.current[:rage_logger]
    end

    let(:log_processor) { described_class.new }
    let(:env) { {} }

    after do
      Thread.current[:rage_logger] = nil
    end

    it "correctly initializes the logger" do
      expect(subject).to match({
        tags: [instance_of(String)],
        context: {},
        request_start: instance_of(Float)
      })
    end

    context "with custom context" do
      context "with a single hash" do
        before do
          log_processor.add_custom_context([{ user_id: 1234 }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234 },
            request_start: instance_of(Float)
          })
        end
      end

      context "with multiple hashes" do
        before do
          log_processor.add_custom_context([{ user_id: 1234 }, { account_id: 5678 }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234, account_id: 5678 },
            request_start: instance_of(Float)
          })
        end
      end

      context "with a single proc" do
        before do
          log_processor.add_custom_context([-> { { user_id: 1234 } }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234 },
            request_start: instance_of(Float)
          })
        end
      end

      context "with multiple procs" do
        before do
          log_processor.add_custom_context([-> { { user_id: 1234 } }, -> { { account_id: 5678 } }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234, account_id: 5678 },
            request_start: instance_of(Float)
          })
        end
      end

      context "with both hashes and procs" do
        before do
          log_processor.add_custom_context([
            { user_id: 1234 },
            -> { { account_id: 5678 } },
            { profile_id: 999, user_role: "admin" }
          ])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 1234, account_id: 5678, profile_id: 999, user_role: "admin" },
            request_start: instance_of(Float)
          })
        end
      end

      context "with a proc expecting env" do
        before do
          log_processor.add_custom_context([->(env) { { user_id: env["user_id"] } }])
        end

        let(:env) { { "user_id" => 12345 } }

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: { user_id: 12345 },
            request_start: instance_of(Float)
          })
        end
      end

      context "with a proc returning nil" do
        context "with one context" do
          before do
            log_processor.add_custom_context([->() { { account_id: 1234 } if false }])
          end

          it "correctly initializes the logger" do
            expect(subject).to match({
              tags: [instance_of(String)],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end

        context "with multiple contexts" do
          before do
            log_processor.add_custom_context([
              { user_id: 1234 },
              ->(env) { { account_id: 5678 } if false },
              ->() { { profile_id: 999 } if false }
            ])
          end

          it "correctly initializes the logger" do
            expect(subject).to match({
              tags: [instance_of(String)],
              context: { user_id: 1234 },
              request_start: instance_of(Float)
            })
          end
        end
      end

      context "with an exception in a context proc" do
        before do
          allow(Rage).to receive(:logger).and_return(double)
        end

        context "with one object" do
          before do
            log_processor.add_custom_context([-> { raise "test" }])
          end

          it "correctly initializes the logger" do
            expect(Rage.logger).to receive(:error).with(/Unhandled exception/)
            expect(subject).to match({
              tags: [instance_of(String)],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end

        context "with multiple objects" do
          before do
            log_processor.add_custom_context([
              { user_id: 1234 },
              -> { raise "test" }
            ])
          end

          it "correctly initializes the logger" do
            expect(Rage.logger).to receive(:error).with(/Unhandled exception/)
            expect(subject).to match({
              tags: [instance_of(String)],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end
      end

      context "with a reset context" do
        before do
          log_processor.add_custom_context([{ user_id: 1234 }])
          log_processor.add_custom_context([])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [instance_of(String)],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end
    end

    context "with custom tags" do
      before do
        allow(Iodine::Rack::Utils).to receive(:gen_request_tag).and_return(request_tag)
      end

      let(:request_tag) { "test-request-id-tag" }

      context "with no custom tags and custom request_id" do
        let(:env) { { "rage.request_id" => "custom-test-id" } }

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: ["custom-test-id"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with a single tag" do
        before do
          log_processor.add_custom_tags(["staging"])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with multiple tags" do
        before do
          log_processor.add_custom_tags(["staging", "admin_api"])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging", "admin_api"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with a single proc" do
        before do
          log_processor.add_custom_tags([-> { "staging" }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with multiple procs" do
        before do
          log_processor.add_custom_tags([-> { "staging" }, -> { "admin_api" }])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging", "admin_api"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with both string tags and procs" do
        before do
          log_processor.add_custom_tags([
            "staging",
            -> { "admin_api" },
            "v1.2.3"
          ])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging", "admin_api", "v1.2.3"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with a proc expecting env" do
        before do
          log_processor.add_custom_tags([->(env) { env["version"] }])
        end

        let(:env) { { "version" => "v1.2.3.4" } }

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "v1.2.3.4"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with a proc returning nil" do
        context "with one tag" do
          before do
            log_processor.add_custom_tags([->() { "staging" if false }])
          end

          it "correctly initializes the logger" do
            expect(subject).to match({
              tags: [request_tag],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end

        context "with multiple contexts" do
          before do
            log_processor.add_custom_tags([
              "staging",
              ->(env) { "admin_api" if false },
              ->() { "v1.2.3" if false }
            ])
          end

          it "correctly initializes the logger" do
            expect(subject).to match({
              tags: [request_tag, "staging"],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end
      end

      context "with a proc returning array" do
        before do
          log_processor.add_custom_tags([
            ->() { ["staging", "admin_api"] },
          ])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag, "staging", "admin_api"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with custom request_id" do
        before do
          log_processor.add_custom_tags(["staging"])
        end

        let(:env) { { "rage.request_id" => "custom-test-id" } }

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: ["custom-test-id", "staging"],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end

      context "with an exception in a tag proc" do
        before do
          allow(Rage).to receive(:logger).and_return(double)
        end

        context "with one object" do
          before do
            log_processor.add_custom_tags([-> { raise "test" }])
          end

          it "correctly initializes the logger" do
            expect(Rage.logger).to receive(:error).with(/Unhandled exception/)
            expect(subject).to match({
              tags: [request_tag],
              context: {},
              request_start: instance_of(Float)
            })
          end

          context "with custom request_id" do
            let(:env) { { "rage.request_id" => "custom-test-id" } }

            it "correctly initializes the logger" do
              expect(Rage.logger).to receive(:error).with(/Unhandled exception/)
              expect(subject).to match({
                tags: ["custom-test-id"],
                context: {},
                request_start: instance_of(Float)
              })
            end
          end
        end

        context "with multiple objects" do
          before do
            log_processor.add_custom_tags([
              "staging",
              -> { raise "test" }
            ])
          end

          it "correctly initializes the logger" do
            expect(Rage.logger).to receive(:error).with(/Unhandled exception/)
            expect(subject).to match({
              tags: [request_tag],
              context: {},
              request_start: instance_of(Float)
            })
          end
        end
      end

      context "with a reset context" do
        before do
          log_processor.add_custom_tags(["staging"])
          log_processor.add_custom_tags([])
        end

        it "correctly initializes the logger" do
          expect(subject).to match({
            tags: [request_tag],
            context: {},
            request_start: instance_of(Float)
          })
        end
      end
    end

    context "with custom context and tags" do
      before do
        log_processor.add_custom_context([{ user_id: 1234, account_id: 5678 }])
        log_processor.add_custom_tags([-> { "staging" }])
      end

      it "correctly initializes the logger" do
        expect(subject).to match({
          tags: [instance_of(String), "staging"],
          context: { user_id: 1234, account_id: 5678 },
          request_start: instance_of(Float)
        })
      end
    end
  end
end

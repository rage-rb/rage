# frozen_string_literal: true

RSpec.describe Rage::Configuration do
  describe "#log_context" do
    subject { described_class.new.log_context }

    describe "#push" do
      context "with no objects" do
        it "returns empty array" do
          expect(subject.objects).to eq([])
        end

        it "allows to add a Hash" do
          context = { user_id: 12345 }
          subject << context

          expect(subject.objects).to eq([context])
        end

        it "allows to add a proc" do
          context = -> { { user_id: 12345 } }
          subject << context

          expect(subject.objects).to eq([context])
        end

        it "allows to add a callable" do
          context_class = Data.define do
            def call
            end
          end
          context = context_class.new
          subject << context

          expect(subject.objects).to eq([context])
        end

        it "allows to add an array" do
          context = [{ account_id: 1 }, { profile_id: 2 }]
          subject << context

          expect(subject.objects).to eq([context[0], context[1]])
        end

        it "removes duplicates" do
          context = [{ account_id: 1 }, { profile_id: 2 }]
          subject << { account_id: 1 } << context

          expect(subject.objects).to eq([context[0], context[1]])
        end
      end

      context "with existing objects" do
        before do
          subject << initial_context
        end

        let(:initial_context) { { account_id: 678 } }

        it "allows to add an object" do
          context = -> { { user_id: 12345 } }
          subject << context

          expect(subject.objects).to eq([initial_context, context])
        end

        it "allows to re-add existing object" do
          subject << initial_context
          expect(subject.objects).to eq([initial_context])
        end
      end

      context "with an invalid object" do
        it "raises an error" do
          expect {
            subject << Class
          }.to raise_error(ArgumentError)

          expect(subject.objects).to be_empty
        end
      end

      context "with an array with invalid object" do
        it "raises an error" do
          expect {
            subject << Class
          }.to raise_error(ArgumentError)

          expect(subject.objects).to be_empty
        end
      end
    end

    describe "#delete" do
      let(:context_1) { { user_id: 1 } }
      let(:context_2) { { account_id: 2 } }
      let(:context_3) { { profile_id: 3 } }

      before do
        subject << context_1 << context_2 << context_3
      end

      it "allows to delete an object" do
        subject.delete(context_2)
        expect(subject.objects).to eq([context_1, context_3])
      end

      it "accepts non-existent objects" do
        subject.delete({})
        expect(subject.objects).to eq([context_1, context_2, context_3])
      end
    end

    describe "#__finalize" do
      let(:config) { described_class.new }

      context "with no context" do
        it "doesn't call log processor" do
          expect(Rage.__log_processor).not_to receive(:add_custom_context)
          config.__finalize
        end

        it "doesn't call logger" do
          allow(Rage.__log_processor).to receive(:dynamic_context).and_return(:test_dynamic_context)
          config.__finalize
          expect(config.logger.dynamic_context).to be_nil
        end
      end

      context "with empty context" do
        before do
          config.log_context << {}
          config.log_context.delete({})
        end

        it "calls log processor with an empty array" do
          expect(Rage.__log_processor).to receive(:add_custom_context).with([])
          config.__finalize
        end

        it "calls logger" do
          allow(Rage.__log_processor).to receive(:dynamic_context).and_return(:test_dynamic_context)
          config.__finalize
          expect(config.logger.dynamic_context).to eq(:test_dynamic_context)
        end
      end

      context "with non-empty context" do
        before do
          config.log_context << context
        end

        let(:context) { { user_id: 123 } }

        it "calls log processor with an empty array" do
          expect(Rage.__log_processor).to receive(:add_custom_context).with([context])
          config.__finalize
        end

        it "calls logger" do
          allow(Rage.__log_processor).to receive(:dynamic_context).and_return(:test_dynamic_context)
          config.__finalize
          expect(config.logger.dynamic_context).to eq(:test_dynamic_context)
        end
      end
    end

    describe "#objects" do
      it "doesn't allow direct modifications of context" do
        context = { user_id: 12345 }
        subject << context

        subject.objects.clear

        expect(subject.objects).to eq([context])
      end
    end
  end

  describe "#log_tags" do
    subject { described_class.new.log_tags }

    describe "#push" do
      context "with no objects" do
        it "returns empty array" do
          expect(subject.objects).to eq([])
        end

        it "allows to add a string" do
          subject << "v1.2.3"

          expect(subject.objects).to eq(["v1.2.3"])
        end

        it "allows to add a proc" do
          tag = -> { "v1.2.3" }
          subject << tag

          expect(subject.objects).to eq([tag])
        end

        it "allows to add a callable" do
          tag_class = Data.define do
            def call
            end
          end
          tag = tag_class.new
          subject << tag

          expect(subject.objects).to eq([tag])
        end

        it "allows to add an array" do
          tags = ["v1.2.3", "admin_api"]
          subject << tags

          expect(subject.objects).to eq([tags[0], tags[1]])
        end
      end

      context "with existing objects" do
        before do
          subject << initial_tag
        end

        let(:initial_tag) { "v1.2.3" }

        it "allows to add an object" do
          tag = -> { "admin_api" }
          subject << tag

          expect(subject.objects).to eq([initial_tag, tag])
        end

        it "allows to re-add existing object" do
          subject << initial_tag
          expect(subject.objects).to eq([initial_tag])
        end
      end

      context "with an invalid object" do
        it "raises an error" do
          expect {
            subject << Class
          }.to raise_error(ArgumentError)

          expect(subject.objects).to be_empty
        end
      end

      context "with an array with invalid object" do
        it "raises an error" do
          expect {
            subject << Class
          }.to raise_error(ArgumentError)

          expect(subject.objects).to be_empty
        end
      end
    end

    describe "#delete" do
      let(:tag_1) { "v1.2.3" }
      let(:tag_2) { "admin_api" }
      let(:tag_3) { "staging" }

      before do
        subject << tag_1 << tag_2 << tag_3
      end

      it "allows to delete an object" do
        subject.delete(tag_2)
        expect(subject.objects).to eq([tag_1, tag_3])
      end

      it "accepts non-existent objects" do
        subject.delete("")
        expect(subject.objects).to eq([tag_1, tag_2, tag_3])
      end
    end

    describe "#__finalize" do
      let(:config) { described_class.new }

      context "with no tags" do
        it "doesn't call log processor" do
          expect(Rage.__log_processor).not_to receive(:add_custom_tags)
          config.__finalize
        end

        it "doesn't call logger" do
          allow(Rage.__log_processor).to receive(:dynamic_tags).and_return(:test_dynamic_tags)
          config.__finalize
          expect(config.logger.dynamic_tags).to be_nil
        end
      end

      context "with empty tags" do
        before do
          config.log_tags << ""
          config.log_tags.delete("")
        end

        it "calls log processor with an empty array" do
          expect(Rage.__log_processor).to receive(:add_custom_tags).with([])
          config.__finalize
        end

        it "calls logger" do
          allow(Rage.__log_processor).to receive(:dynamic_tags).and_return(:test_dynamic_tags)
          config.__finalize
          expect(config.logger.dynamic_tags).to eq(:test_dynamic_tags)
        end
      end

      context "with non-empty tags" do
        before do
          config.log_tags << "staging"
        end

        it "calls log processor with an empty array" do
          expect(Rage.__log_processor).to receive(:add_custom_tags).with(["staging"])
          config.__finalize
        end

        it "calls logger" do
          allow(Rage.__log_processor).to receive(:dynamic_tags).and_return(:test_dynamic_tags)
          config.__finalize
          expect(config.logger.dynamic_tags).to eq(:test_dynamic_tags)
        end
      end
    end

    describe "#objects" do
      it "doesn't allow direct modifications of tags" do
        subject << "staging"
        subject.objects.clear

        expect(subject.objects).to eq(["staging"])
      end
    end
  end

  describe "#logger" do
    subject { described_class.new }

    context "with nil" do
      it "correctly sets logger" do
        subject.logger = nil
        expect(subject.logger).to be_nil

        subject.__finalize
        expect(subject.logger).to be_a(Rage::Logger)
      end
    end

    context "with Rage::Logger" do
      it "correctly sets logger" do
        logger = Rage::Logger.new(nil)
        subject.logger = logger
        expect(subject.logger).to equal(logger)
      end
    end

    context "with callable" do
      it "correctly sets logger" do
        logger = proc {}
        subject.logger = logger

        expect(subject.logger).to be_a(Rage::Logger)
        expect(subject.logger.external_logger).to be_a(Rage::Logger::External::Dynamic)
        expect(subject.logger.external_logger.wrapped).to equal(logger)
      end
    end

    context "with logger" do
      it "correctly sets logger" do
        logger = ::Logger.new(nil)
        subject.logger = logger

        expect(subject.logger).to be_a(Rage::Logger)
        expect(subject.logger.external_logger).to be_a(Rage::Logger::External::Static)
        expect(subject.logger.external_logger.wrapped).to equal(logger)
      end
    end

    context "with invalid logger" do
      it "raises an error" do
        expect {
          subject.logger = "test"
        }.to raise_error(ArgumentError)
      end
    end

    context "with missing methods" do
      let(:logger_class) do
        Class.new do
          def debug(_) = true
          def warn(_) = true
          def error(_) = true
          def fatal(_) = true
          def unknown(_) = true
        end
      end

      it "raises an error" do
        expect {
          subject.logger = logger_class.new
        }.to raise_error(ArgumentError)
      end
    end

    context "with formatter set" do
      it "prints a warning" do
        subject.logger = proc {}
        subject.log_formatter = proc {}

        expect {
          subject.__finalize
        }.to output(/changing the log formatter via `config.log_formatter=` has no effect/).to_stdout
      end
    end
  end

  describe "MiddlewareRegistry" do
    subject { described_class::MiddlewareRegistry.new }

    context "#use" do
      context "with no middleware" do
        it "correctly adds a middleware" do
          subject.use :test_middleware
          expect(subject.objects).to match([[:test_middleware, anything, anything]])
        end

        context "with one middleware" do
          before do
            subject.use :first_middleware
          end

          it "correctly adds a middleware" do
            subject.use :second_middleware

            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end
        end

        context "with two middleware" do
          before do
            subject.use :first_middleware
            subject.use :second_middleware
          end

          it "correctly adds a middleware" do
            subject.use :third_middleware

            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything],
              [:third_middleware, anything, anything]
            ])
          end
        end

        context "with arguments" do
          it "correctly adds a middleware" do
            test_block = proc {}
            subject.use :test_middleware, 11, 22, 33, &test_block

            expect(subject.objects).to match([[:test_middleware, [11, 22, 33], test_block]])
          end
        end
      end
    end

    context "#insert_before" do
      context "with no middleware" do
        context "with index" do
          it "correctly adds a middleware before 0" do
            subject.insert_before(0, :test_middleware)
            expect(subject.objects).to match([[:test_middleware, anything, anything]])
          end

          it "checks for existing index" do
            expect {
              subject.insert_before(-1, :test_middleware)
            }.to raise_error(ArgumentError, /Could not find middleware at index -1/)
          end
        end

        context "with middleware" do
          it "checks for existing middleware" do
            expect {
              subject.insert_before(:first_middleware, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find `first_middleware`/)
          end
        end
      end

      context "with one middleware" do
        before do
          subject.use :first_middleware
        end

        context "with index" do
          it "correctly adds a middleware before 0" do
            subject.insert_before(0, :second_middleware)
            expect(subject.objects).to match([
              [:second_middleware, anything, anything],
              [:first_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware before -1" do
            subject.insert_before(-1, :second_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "raises error with incorrect index" do
            expect {
              subject.insert_before(10, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find middleware at index 10/)
          end
        end

        context "with middleware" do
          it "correctly adds a middleware before existing middleware" do
            subject.insert_before(:first_middleware, :second_middleware)
            expect(subject.objects).to match([
              [:second_middleware, anything, anything],
              [:first_middleware, anything, anything]
            ])
          end

          it "checks for existing middleware" do
            expect {
              subject.insert_before(:third_middleware, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find `third_middleware`/)
          end
        end
      end

      context "with two middleware" do
        before do
          subject.use :first_middleware
          subject.use :second_middleware
        end

        context "with index" do
          it "correctly adds a middleware before 0" do
            subject.insert_before(0, :third_middleware)
            expect(subject.objects).to match([
              [:third_middleware, anything, anything],
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware before -1" do
            subject.insert_before(-1, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything],
              [:third_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware before 1" do
            subject.insert_before(1, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:third_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end
        end

        context "with middleware" do
          it "correctly adds a middleware before existing middleware" do
            subject.insert_before(:second_middleware, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:third_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware before existing middleware" do
            subject.insert_before(:first_middleware, :third_middleware)
            expect(subject.objects).to match([
              [:third_middleware, anything, anything],
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end
        end
      end
    end

    context "#insert_after" do
      context "with no middleware" do
        context "with index" do
          it "correctly adds a middleware before 0" do
            subject.insert_after(0, :test_middleware)
            expect(subject.objects).to match([[:test_middleware, anything, anything]])
          end

          it "checks for existing index" do
            expect {
              subject.insert_after(-1, :test_middleware)
            }.to raise_error(ArgumentError, /Could not find middleware at index -1/)
          end
        end

        context "with middleware" do
          it "checks for existing middleware" do
            expect {
              subject.insert_after(:first_middleware, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find `first_middleware`/)
          end
        end
      end

      context "with one middleware" do
        before do
          subject.use :first_middleware
        end

        context "with index" do
          it "correctly adds a middleware after 0" do
            subject.insert_after(0, :second_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware after -1" do
            subject.insert_after(-1, :second_middleware)
            expect(subject.objects).to match([
              [:second_middleware, anything, anything],
              [:first_middleware, anything, anything]
            ])
          end

          it "raises error with incorrect index" do
            expect {
              subject.insert_after(10, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find middleware at index 10/)
          end
        end

        context "with middleware" do
          it "correctly adds a middleware after existing middleware" do
            subject.insert_after(:first_middleware, :second_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "checks for existing middleware" do
            expect {
              subject.insert_after(:third_middleware, :second_middleware)
            }.to raise_error(ArgumentError, /Could not find `third_middleware`/)
          end
        end
      end

      context "with two middleware" do
        before do
          subject.use :first_middleware
          subject.use :second_middleware
        end

        context "with index" do
          it "correctly adds a middleware after 0" do
            subject.insert_after(0, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:third_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware after -1" do
            subject.insert_after(-1, :third_middleware)
            expect(subject.objects).to match([
              [:third_middleware, anything, anything],
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware after 1" do
            subject.insert_after(1, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything],
              [:third_middleware, anything, anything]
            ])
          end
        end

        context "with middleware" do
          it "correctly adds a middleware after existing middleware" do
            subject.insert_after(:second_middleware, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:second_middleware, anything, anything],
              [:third_middleware, anything, anything]
            ])
          end

          it "correctly adds a middleware after existing middleware" do
            subject.insert_after(:first_middleware, :third_middleware)
            expect(subject.objects).to match([
              [:first_middleware, anything, anything],
              [:third_middleware, anything, anything],
              [:second_middleware, anything, anything]
            ])
          end
        end
      end
    end

    context "#include?" do
      context "with no middleware" do
        it "correctly checks if a middleware is in the stack" do
          expect(subject).not_to include(:first_middleware)
        end
      end

      context "with existing middleware" do
        before do
          subject.use :first_middleware
        end

        it "correctly checks if a middleware is in the stack" do
          expect(subject).to include(:first_middleware)
        end

        it "correctly checks if a middleware is not in the stack" do
          expect(subject).not_to include(:second_middleware)
        end
      end

      context "with arguments" do
        before do
          subject.use :first_middleware, 111 do
          end
        end

        it "correctly checks if a middleware is in the stack" do
          expect(subject).to include(:first_middleware)
        end
      end
    end

    context "#delete" do
      context "with no middleware" do
        it "doesn't raise error" do
          expect {
            subject.delete :test_middleware
          }.not_to raise_error
        end
      end

      context "with existing middleware" do
        before do
          subject.use :first_middleware
        end

        it "correctly deletes existing middleware" do
          subject.delete :first_middleware
          expect(subject.objects).to be_empty
        end

        it "doesn't raise with unknown middleware" do
          subject.delete :second_middleware
          expect(subject.objects).to match([[:first_middleware, anything, anything]])
        end
      end

      context "with duplicates" do
        before do
          subject.use :first_middleware
          subject.use :second_middleware
          subject.use :first_middleware, 111 do
          end
        end

        it "correctly deletes existing middleware" do
          subject.delete :first_middleware
          expect(subject.objects).to match([[:second_middleware, anything, anything]])
        end
      end
    end
  end

  describe "Middleware" do
    subject { described_class::Middleware.new }

    context "with new object" do
      it "returns default middleware" do
        expect(subject.middlewares).to eq([[Rage::FiberWrapper]])
      end

      it "allows to add middleware" do
        subject.use :new_middleware
        expect(subject.middlewares).to match([[Rage::FiberWrapper], [:new_middleware, anything, anything]])
      end

      it "allows to append middleware" do
        subject.insert_after(Rage::FiberWrapper, :new_middleware)
        expect(subject.middlewares).to match([[Rage::FiberWrapper], [:new_middleware, anything, anything]])
      end

      it "allows to prepend middleware" do
        expect {
          subject.insert_before(Rage::FiberWrapper, :new_middleware)
        }.to output(/WARNING: inserting the `new_middleware` middleware before `Rage::FiberWrapper` may cause undefined behavior/).to_stdout

        expect(subject.middlewares).to match([[:new_middleware, anything, anything], [Rage::FiberWrapper]])
      end
    end
  end

  describe "Rack::Events" do
    subject { config.__finalize }

    let(:config) { described_class.new }

    context "without Rack::Events" do
      it "doesn't add Rage::BodyFinalizer" do
        subject
        expect(config.middleware).not_to include(Rage::BodyFinalizer)
      end
    end

    context "with Rack::Events" do
      before do
        stub_const("Rack::Events", double)
      end

      context "if Rack::Events is in middleware stack" do
        before do
          config.middleware.use Rack::Events
        end

        it "adds Rage::BodyFinalizer" do
          subject
          expect(config.middleware).to include(Rage::BodyFinalizer)
        end

        it "places Rage::BodyFinalizer before Rack::Events" do
          subject

          rack_events_index = config.middleware.objects.index { |middleware, _, _| middleware == Rack::Events }
          body_finalizer_index = config.middleware.objects.index { |middleware, _, _| middleware == Rage::BodyFinalizer }

          expect(body_finalizer_index).to be < rack_events_index
        end
      end

      context "if Rack::Events is not in middleware stack" do
        it "doesn't add Rage::BodyFinalizer" do
          subject
          expect(config.middleware).not_to include(Rage::BodyFinalizer)
        end
      end

      context "if Rack::Events is moved" do
        before do
          config.middleware.use proc {}
          config.middleware.use proc {}
          config.middleware.use Rack::Events
        end

        it "updates the position of Rage::BodyFinalizer" do
          config.__finalize
          config.middleware.delete(Rack::Events)
          config.middleware.insert_after(0, Rack::Events)
          config.__finalize

          rack_events_index = config.middleware.objects.index { |middleware, _, _| middleware == Rack::Events }
          body_finalizer_index = config.middleware.objects.index { |middleware, _, _| middleware == Rage::BodyFinalizer }

          expect(body_finalizer_index).to be < rack_events_index
        end
      end
    end
  end

  describe "#deferred" do
    context "#enqueue_middleware" do
      subject { described_class.new.deferred.enqueue_middleware }

      it "adds a middleware" do
        middleware_class = Class.new do
          def call
          end
        end

        expect { subject.use(middleware_class) }.to change { subject.objects }.to([[middleware_class, [], nil]])
      end

      it "adds a middleware with arguments" do
        middleware_class = Class.new do
          def call
          end
        end

        expect {
          subject.use(middleware_class, option_1: 11, option_2: 222) do
          end
        }.to change {
          subject.objects
        }.to([[middleware_class, [{ option_1: 11, option_2: 222 }], instance_of(Proc)]])
      end

      it "doesn't accept instances" do
        middleware_class = Class.new do
          def call
          end
        end

        expect { subject.use(middleware_class.new) }.to raise_error(ArgumentError, /has to be a class/)
      end

      it "doesn't accept classes without the call method" do
        middleware_class = Class.new
        expect { subject.use(middleware_class) }.to raise_error(ArgumentError, /has to implement the `#call` method/)
      end
    end

    context "#perform_middleware" do
      subject { described_class.new.deferred.perform_middleware }

      it "adds a middleware" do
        middleware_class = Class.new do
          def call
          end
        end

        expect { subject.use(middleware_class) }.to change { subject.objects }.to([[middleware_class, anything, anything]])
      end

      it "adds a middleware with arguments" do
        middleware_class = Class.new do
          def call
          end
        end

        expect {
          subject.use(middleware_class, option_1: 11, option_2: 222) do
          end
        }.to change {
          subject.objects
        }.to([[middleware_class, [{ option_1: 11, option_2: 222 }], instance_of(Proc)]])
      end

      it "doesn't accept instances" do
        middleware_class = Class.new do
          def call
          end
        end

        expect { subject.use(middleware_class.new) }.to raise_error(ArgumentError, /has to be a class/)
      end

      it "doesn't accept classes without the call method" do
        middleware_class = Class.new
        expect { subject.use(middleware_class) }.to raise_error(ArgumentError, /has to implement the `#call` method/)
      end
    end
  end

  describe "#telemetry" do
    subject { described_class.new.telemetry }

    context "with no telemetry handlers" do
      it "returns empty object" do
        expect(subject.handlers_map).to be_empty
        expect(subject.handlers_map["controller.action.process"]).to be_nil
      end
    end

    context "with one telemetry handler" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test_handler

          def test_handler
          end
        end
      end

      it "correctly adds handler" do
        handler_instance = handler.new

        subject.use(handler_instance)

        expect(subject.handlers_map).to eq({
          "controller.action.process" => [Rage::Telemetry::HandlerRef[handler_instance, :test_handler]]
        })
      end
    end

    context "with multiple telemetry handlers" do
      let(:handler_1) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test_handler_1

          def test_handler_1
          end
        end
      end

      let(:handler_2) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test_handler_2
          handle "events.event.publish", with: :test_handler_3

          def test_handler_2
          end

          def test_handler_3
          end
        end
      end

      it "correctly adds handlers" do
        handler_instance_1 = handler_1.new
        handler_instance_2 = handler_2.new

        subject.use(handler_instance_1)
        subject.use(handler_instance_2)

        expect(subject.handlers_map).to eq({
          "controller.action.process" => [
            Rage::Telemetry::HandlerRef[handler_instance_1, :test_handler_1],
            Rage::Telemetry::HandlerRef[handler_instance_2, :test_handler_2]
          ],
          "events.event.publish" => [
            Rage::Telemetry::HandlerRef[handler_instance_2, :test_handler_3]
          ]
        })
      end
    end

    context "with handler class" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test_handler

          def self.test_handler
          end
        end
      end

      it "correctly adds handler" do
        subject.use(handler)

        expect(subject.handlers_map).to eq({
          "controller.action.process" => [Rage::Telemetry::HandlerRef[handler, :test_handler]]
        })
      end
    end

    context "with no handler methods" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
        end
      end

      context "with handler class" do
        it "raises an exception" do
          expect {
            subject.use(handler)
          }.to raise_error(/does not define any handlers/)
        end
      end

      context "with handler instance" do
        it "raises an exception" do
          expect {
            subject.use(handler.new)
          }.to raise_error(/does not define any handlers/)
        end
      end
    end

    context "with incorrect handler" do
      let(:handler) do
        Class.new
      end

      context "with handler class" do
        it "raises an exception" do
          expect {
            subject.use(handler)
          }.to raise_error(/should inherit `Rage::Telemetry::Handler`/)
        end
      end

      context "with handler instance" do
        it "raises an exception" do
          expect {
            subject.use(handler.new)
          }.to raise_error(/should inherit `Rage::Telemetry::Handler`/)
        end
      end
    end

    context "with incorrect handler method" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test_handler
        end
      end

      context "with handler class" do
        it "raises an exception" do
          expect {
            subject.use(handler)
          }.to raise_error(/does not implement the `test_handler` handler method/)
        end
      end

      context "with handler instance" do
        it "raises an exception" do
          expect {
            subject.use(handler.new)
          }.to raise_error(/does not implement the `test_handler` handler method/)
        end
      end
    end
  end

  describe "#session" do
    subject { described_class.new.session }

    context "#key" do
      it "returns nil by default" do
        expect(subject.key).to be_nil
      end

      it "persists configuration" do
        subject.key = "_my_test"
        expect(subject.key).to eq("_my_test")
      end
    end
  end
end

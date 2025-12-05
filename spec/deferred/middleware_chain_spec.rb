# frozen_string_literal: true

RSpec.describe Rage::Deferred::MiddlewareChain do
  subject { described_class.new(enqueue_middleware:, perform_middleware:) }

  let(:enqueue_middleware) { [] }
  let(:perform_middleware) { [] }

  let(:args) { [] }
  let(:kwargs) { {} }
  let(:task_class) { Class.new }
  let(:context) { Rage::Deferred::Context.build(task_class, args, kwargs) }

  after do
    subject
  end

  context "Enqueue Chain" do
    context "with no middleware" do
      it "passes control to the task" do
        expect { |block| subject.with_enqueue_middleware(context, delay: nil, delay_until: nil, &block) }.to yield_control
      end
    end

    context "with middleware" do
      let(:verifier) { double }
      let(:enqueue_middleware) { [middleware_class] }
      let(:middleware_class) do
        Class.new do
          def call(**params)
            verifier.call(params)
            yield
          end
        end
      end

      before do
        allow_any_instance_of(middleware_class).to receive(:verifier).and_return(verifier)
      end

      it "calls middleware with correct arguments" do
        expect(verifier).to receive(:call) do |data|
          expect(data[:phase]).to eq(:enqueue)
          expect(data[:args]).to eq([])
          expect(data[:kwargs]).to eq({})
          expect(data[:context]).to eq({})
          expect(data[:task_class]).to eq(task_class)
          expect(data[:delay]).to be_nil
          expect(data[:delay_until]).to be_nil
        end

        subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
      end

      it "passes control to the task" do
        allow(verifier).to receive(:call)
        expect { |block| subject.with_enqueue_middleware(context, delay: nil, delay_until: nil, &block) }.to yield_control
      end

      context "with no yield" do
        let(:middleware_class) do
          Class.new do
            def call(**)
            end
          end
        end

        it "doesn't pass control to the task" do
          expect { |block| subject.with_enqueue_middleware(context, delay: nil, delay_until: nil, &block) }.not_to yield_control
        end
      end

      context "with delay and delay_until options" do
        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call) do |data|
            expect(data[:delay]).to eq(11)
            expect(data[:delay_until]).to eq(22)
          end

          subject.with_enqueue_middleware(context, delay: 11, delay_until: 22) {}
        end
      end

      context "with subset of parameters" do
        let(:middleware_class) do
          Class.new do
            def call(phase:, task_class:)
              verifier.call({ phase:, task_class: })
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call) do |data|
            expect(data[:phase]).to eq(:enqueue)
            expect(data[:task_class]).to eq(task_class)
          end

          subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
        end
      end

      context "with no parameters" do
        let(:middleware_class) do
          Class.new do
            def call
              verifier.call
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call)
          subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
        end
      end

      context "with task arguments" do
        let(:args) { :test_args }
        let(:kwargs) { :test_kwargs }
        let(:middleware_class) do
          Class.new do
            def call(args:, kwargs:)
              verifier.call({ args:, kwargs: })
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call) do |data|
            expect(data[:args]).to eq(:test_args)
            expect(data[:kwargs]).to eq(:test_kwargs)
          end

          subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
        end
      end

      context "with middleware arguments" do
        context "with arguments" do
          let(:enqueue_middleware) { [[middleware_class, [{ test_key_1: 11, test_key_2: 222 }], nil]] }
          let(:middleware_class) do
            Class.new do
              def initialize(options)
                verifier.call_initialize(options)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with({ test_key_1: 11, test_key_2: 222 })
            subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
          end
        end

        context "with block" do
          let(:block) { proc {} }
          let(:enqueue_middleware) { [[middleware_class, [], block]] }
          let(:middleware_class) do
            Class.new do
              def initialize(&block)
                verifier.call_initialize(block)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with(block)
            subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
          end
        end

        context "with arguments and block" do
          let(:block) { proc {} }
          let(:enqueue_middleware) { [[middleware_class, [{ test_key_1: 11, test_key_2: 222 }], block]] }
          let(:middleware_class) do
            Class.new do
              def initialize(options, &block)
                verifier.call_initialize(options, block)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with({ test_key_1: 11, test_key_2: 222 }, block)
            subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
          end
        end
      end
    end

    context "with middleware chain" do
      let(:verifier) { double }
      let(:enqueue_middleware) { [middleware_class_1, middleware_class_2] }
      let(:middleware_class_1) do
        Class.new do
          def call(phase:, context:)
            verifier.call_1({ phase:, context: })
            context[:test_key] = true
            yield
          end
        end
      end
      let(:middleware_class_2) do
        Class.new do
          def call(kwargs:, context:)
            verifier.call_2({ kwargs:, context: })
            yield
          end
        end
      end

      before do
        allow_any_instance_of(middleware_class_1).to receive(:verifier).and_return(verifier)
        allow_any_instance_of(middleware_class_2).to receive(:verifier).and_return(verifier)
      end

      it "calls middleware with correct arguments" do
        expect(verifier).to receive(:call_1) do |data|
          expect(data[:phase]).to eq(:enqueue)
          expect(data[:context]).to eq({})
        end

        expect(verifier).to receive(:call_2) do |data|
          expect(data[:kwargs]).to eq({})
          expect(data[:context]).to eq({ test_key: true })
        end

        subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
      end

      it "calls middleware in the correct order" do
        expect(verifier).to receive(:call_1).ordered
        expect(verifier).to receive(:call_2).ordered

        subject.with_enqueue_middleware(context, delay: nil, delay_until: nil) {}
      end
    end
  end

  context "Perform Chain" do
    let(:task) { task_class.new }

    context "with no middleware" do
      it "passes control to the task" do
        expect { |block| subject.with_perform_middleware(context, task:, &block) }.to yield_control
      end
    end

    context "with middleware" do
      let(:verifier) { double }
      let(:perform_middleware) { [middleware_class] }
      let(:middleware_class) do
        Class.new do
          def call(**params)
            verifier.call(params)
            yield
          end
        end
      end

      before do
        allow_any_instance_of(middleware_class).to receive(:verifier).and_return(verifier)
      end

      it "calls middleware with correct arguments" do
        expect(verifier).to receive(:call) do |data|
          expect(data[:phase]).to eq(:perform)
          expect(data[:args]).to eq([])
          expect(data[:kwargs]).to eq({})
          expect(data[:context]).to eq({})
          expect(data[:task_class]).to eq(task_class)
          expect(data[:task]).to eq(task)
        end

        subject.with_perform_middleware(context, task:) {}
      end

      it "passes control to the task" do
        allow(verifier).to receive(:call)
        expect { |block| subject.with_perform_middleware(context, task:, &block) }.to yield_control
      end

      context "with no yield" do
        let(:middleware_class) do
          Class.new do
            def call(**)
            end
          end
        end

        it "doesn't pass control to the task" do
          expect { |block| subject.with_perform_middleware(context, task:, &block) }.not_to yield_control
        end
      end

      context "with subset of parameters" do
        let(:middleware_class) do
          Class.new do
            def call(phase:, task:)
              verifier.call({ phase:, task: })
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call) do |data|
            expect(data[:phase]).to eq(:perform)
            expect(data[:task]).to eq(task)
          end

          subject.with_perform_middleware(context, task:) {}
        end
      end

      context "with no parameters" do
        let(:middleware_class) do
          Class.new do
            def call
              verifier.call
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call)
          subject.with_perform_middleware(context, task:) {}
        end
      end

      context "with task arguments" do
        let(:args) { :test_args }
        let(:kwargs) { :test_kwargs }
        let(:middleware_class) do
          Class.new do
            def call(args:, kwargs:)
              verifier.call({ args:, kwargs: })
            end
          end
        end

        it "calls middleware with correct arguments" do
          expect(verifier).to receive(:call) do |data|
            expect(data[:args]).to eq(:test_args)
            expect(data[:kwargs]).to eq(:test_kwargs)
          end

          subject.with_perform_middleware(context, task:) {}
        end
      end

      context "with middleware arguments" do
        context "with arguments" do
          let(:perform_middleware) { [[middleware_class, [{ test_key_1: 11, test_key_2: 222 }], nil]] }
          let(:middleware_class) do
            Class.new do
              def initialize(options)
                verifier.call_initialize(options)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with({ test_key_1: 11, test_key_2: 222 })
            subject.with_perform_middleware(context, task:) {}
          end
        end

        context "with block" do
          let(:block) { proc {} }
          let(:perform_middleware) { [[middleware_class, [], block]] }
          let(:middleware_class) do
            Class.new do
              def initialize(&block)
                verifier.call_initialize(block)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with(block)
            subject.with_perform_middleware(context, task:) {}
          end
        end

        context "with arguments and block" do
          let(:block) { proc {} }
          let(:perform_middleware) { [[middleware_class, [{ test_key_1: 11, test_key_2: 222 }], block]] }
          let(:middleware_class) do
            Class.new do
              def initialize(options, &block)
                verifier.call_initialize(options, block)
              end

              def call(**)
              end
            end
          end

          it "initializes middleware with correct arguments" do
            expect(verifier).to receive(:call_initialize).with({ test_key_1: 11, test_key_2: 222 }, block)
            subject.with_perform_middleware(context, task:) {}
          end
        end
      end
    end

    context "with middleware chain" do
      let(:verifier) { double }
      let(:perform_middleware) { [middleware_class_1, middleware_class_2] }
      let(:middleware_class_1) do
        Class.new do
          def call(phase:, task:, context:)
            verifier.call_1({ phase:, task:, context: })
            context[:test_key] = true
            yield
          end
        end
      end
      let(:middleware_class_2) do
        Class.new do
          def call(context:)
            verifier.call_2({ context: })
            yield
          end
        end
      end

      before do
        allow_any_instance_of(middleware_class_1).to receive(:verifier).and_return(verifier)
        allow_any_instance_of(middleware_class_2).to receive(:verifier).and_return(verifier)
      end

      it "calls middleware with correct arguments" do
        expect(verifier).to receive(:call_1) do |data|
          expect(data[:phase]).to eq(:perform)
          expect(data[:task]).to eq(task)
          expect(data[:context]).to eq({})
        end

        expect(verifier).to receive(:call_2) do |data|
          expect(data[:context]).to eq({ test_key: true })
        end

        subject.with_perform_middleware(context, task:) {}
      end

      it "calls middleware in the correct order" do
        expect(verifier).to receive(:call_1).ordered
        expect(verifier).to receive(:call_2).ordered

        subject.with_perform_middleware(context, task:) {}
      end
    end
  end
end

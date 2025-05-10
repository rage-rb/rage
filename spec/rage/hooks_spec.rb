# frozen_string_literal: true

RSpec.describe Hooks do
  class ClassWithHooks; include Hooks; end

  subject { ClassWithHooks.new }

  describe "#push_hook" do
    it "stores hook by family" do
      hook = proc { 1 }
      subject.push_hook(hook, :after)
      subject.push_hook(1, :after)
      subject.push_hook(hook, :before)
      subject.push_hook(nil, :before)

      expect(subject.instance_variable_get(:@hooks)).to eq({ after: [hook], before: [hook] })
    end
  end

  describe "#run_hooks_for!" do
    context "hooks families" do
      let(:before_proc) { proc { 2 } }
      let(:after_proc) { proc { 1 } }

      before do
        subject.push_hook(after_proc, :after)
        subject.push_hook(before_proc, :before)

        allow(after_proc).to receive(:call).with(no_args)
        allow(before_proc).to receive(:call).with(no_args)

        subject.run_hooks_for!(:after)
      end

      it "runs hooks for the given family" do
        expect(after_proc).to have_received(:call).with(no_args)
      end

      it 'clears hooks after run for the executed hooks family ' do
        hooks = subject.instance_variable_get(:@hooks)

        expect(hooks[:after]).to eq([])
      end

      it "does not run hooks for other families" do
        expect(before_proc).not_to have_received(:call).with(no_args)
      end
    end

    context "hooks context" do
      let(:after_proc) { proc { 1 } }

      before do
        allow(after_proc).to receive(:call).with(no_args)
      end

      context "when context is given" do
        let(:context) { Class.new }

        before do
          subject.push_hook(after_proc, :after)

          allow(context).to receive(:instance_exec)
          allow(context).to receive(:instance_exec).with(after_proc)

          subject.run_hooks_for!(:after, context)
        end

        it "executes hook in the context of the provided context" do
          expect(context).to have_received(:instance_exec) do |*_, &block|
            expect(block).to eq(after_proc)
          end
        end
      end

      context "when context is not given" do
        before do
          subject.push_hook(after_proc, :after)

          subject.run_hooks_for!(:after)
        end

        it "executes hook without context" do
          expect(after_proc).to have_received(:call)
        end
      end
    end
  end
end

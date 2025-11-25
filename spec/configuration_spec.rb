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
end

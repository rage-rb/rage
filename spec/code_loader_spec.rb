# frozen_string_literal: true

RSpec.describe Rage::CodeLoader do
  subject { Rage.code_loader }

  let(:app_path) { "#{Dir.tmpdir}/app" }

  before do
    allow(Rage.root).to receive(:join).with("app").and_return(Pathname.new(app_path))
    FileUtils.mkdir(app_path)
  end

  after do
    FileUtils.remove_entry(app_path)
  end

  describe "check_updated!" do
    context "when there are no files" do
      it "returns false on the first call" do
        expect(subject.check_updated!).to be(false)
      end

      context "when a new file is added" do
        before do
          subject.check_updated!
          File.write("#{app_path}/test.rb", "")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when existing file is updated" do
        before do
          File.write("#{app_path}/test.rb", "")
          subject.check_updated!
          sleep 0.1
          FileUtils.touch("#{app_path}/test.rb")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when existing file is removed" do
        before do
          File.write("#{app_path}/test.rb", "")
          subject.check_updated!
          FileUtils.rm("#{app_path}/test.rb")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end
    end

    context "when there are existing files" do
      before do
        File.write("#{app_path}/test.rb", "")
        FileUtils.mkpath("#{app_path}/models/concerns")
      end

      after do
        FileUtils.remove_entry("#{app_path}/models/concerns")
      end

      context "when a new file is added" do
        before do
          subject.check_updated!
          File.write("#{app_path}/models/concerns/test.rb", "")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when existing file is updated" do
        before do
          File.write("#{app_path}/models/concerns/test.rb", "")
          subject.check_updated!
          sleep 0.1
          FileUtils.touch("#{app_path}/models/concerns/test.rb")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when existing file is removed" do
        before do
          File.write("#{app_path}/models/concerns/test.rb", "")
          subject.check_updated!
          FileUtils.rm("#{app_path}/models/concerns/test.rb")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end
    end

    context "with reload_paths configured" do
      let(:root_path) { Dir.tmpdir }
      let(:views_path) { "#{root_path}/app/views" }

      before do
        allow(Rage).to receive(:root).and_return(Pathname.new(root_path))
        FileUtils.mkpath(views_path)
        Rage.config.code_loader.reload_paths = ["app/views/**/*.haml"]
      end

      after do
        FileUtils.remove_entry(views_path)
        Rage.config.code_loader.reload_paths = []
      end

      context "when a template file is added" do
        before do
          subject.check_updated!
          File.write("#{views_path}/index.html.haml", "%h1 Hello")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when a template file is updated" do
        before do
          File.write("#{views_path}/index.html.haml", "%h1 Hello")
          subject.check_updated!
          sleep 0.1
          FileUtils.touch("#{views_path}/index.html.haml")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when a template file is removed" do
        before do
          File.write("#{views_path}/index.html.haml", "%h1 Hello")
          subject.check_updated!
          FileUtils.rm("#{views_path}/index.html.haml")
        end

        it "returns true" do
          expect(subject.check_updated!).to be(true)
        end

        it "updates internal state" do
          expect(subject.check_updated!).to be(true)
          expect(subject.check_updated!).to be(false)
        end
      end

      context "when a non-matching file is added" do
        before do
          subject.check_updated!
          File.write("#{views_path}/index.html.slim", "h1 Hello")
        end

        it "returns false" do
          expect(subject.check_updated!).to be(false)
        end
      end
    end
  end

  describe "#reload_in_background" do
    subject(:code_loader) { described_class.new }

    let(:timer) { [] }
    let(:logger) { double(error: nil) }

    before do
      allow(Iodine).to receive(:run_every) { |_, &block| timer << block }
      allow(Rage).to receive(:logger).and_return(logger)
    end

    def tick
      timer.each(&:call)
    end

    context "without a loader" do
      it "doesn't schedule a timer" do
        code_loader.reload_in_background
        expect(Iodine).not_to have_received(:run_every)
      end
    end

    context "with a loader" do
      before do
        code_loader.instance_variable_set(:@loader, double)
        code_loader.check_updated!
        code_loader.reload_in_background
      end

      it "reloads the code when it changes" do
        expect(code_loader).to receive(:reload).once

        tick
        File.write("#{app_path}/test.rb", "")
        tick
        tick
      end

      context "when the reload fails" do
        before do
          allow(code_loader).to receive(:reload).and_raise(SyntaxError, "routes.rb: unexpected end-of-input")
          File.write("#{app_path}/test.rb", "")
          tick
        end

        it "logs the error" do
          expect(logger).to have_received(:error).with(/Failed to reload code, the next request will retry: SyntaxError/)
        end

        it "lets the next request retry the reload" do
          expect(code_loader.check_updated!).to be(true)
          expect(code_loader.check_updated!).to be(false)
        end

        it "doesn't retry the reload in the background until the files change again" do
          tick
          tick
          expect(code_loader).to have_received(:reload).once

          File.write("#{app_path}/test2.rb", "")
          tick
          expect(code_loader).to have_received(:reload).twice
        end
      end

      it "doesn't start a reload while another one is in progress" do
        code_loader.instance_variable_set(:@reload_in_progress, true)
        File.write("#{app_path}/test.rb", "")
        expect(code_loader).not_to receive(:reload)

        tick
      end
    end
  end

  describe "#reload" do
    subject(:code_loader) { described_class.new }

    it "clears a pending failed background reload" do
      code_loader.instance_variable_set(:@loader, double(reload: nil))
      code_loader.instance_variable_set(:@background_reload_failed, true)
      allow(Rage.__router).to receive(:reset_routes)
      allow(code_loader).to receive(:load)
      allow(code_loader).to receive(:reload_components)
      allow(Rage.config).to receive(:run_hooks_for)

      code_loader.reload

      expect(code_loader.check_updated!).to be(false)
    end
  end

  describe "#reloadable?" do
    subject(:code_loader) { described_class.new }

    it "returns nil without a loader" do
      expect(code_loader.reloadable?("TestDaemon")).to be_nil
    end

    it "delegates to the loader" do
      loader = double
      allow(loader).to receive(:unloadable_cpath?).with("TestDaemon").and_return(true)
      code_loader.instance_variable_set(:@loader, loader)

      expect(code_loader.reloadable?("TestDaemon")).to be(true)
    end
  end
end

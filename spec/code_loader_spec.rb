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
    let(:daemon_file) { "#{app_path}/test_daemon.rb" }
    let(:watched_files) { [daemon_file] }

    before do
      File.write(daemon_file, "")
      allow(Iodine).to receive(:run_every) { |_, &block| timer << block }
      allow(Rage).to receive(:logger).and_return(logger)
    end

    def tick
      timer.each(&:call)
    end

    def touch(path)
      time = Time.now + rand(10..1000)
      File.write(path, "") unless File.exist?(path)
      File.utime(time, time, path)
    end

    context "without a loader" do
      it "doesn't schedule a timer" do
        code_loader.reload_in_background { watched_files }
        expect(Iodine).not_to have_received(:run_every)
      end
    end

    context "with a loader" do
      before do
        code_loader.instance_variable_set(:@loader, double)
        code_loader.check_updated!
        code_loader.reload_in_background { watched_files }
      end

      it "reloads the code when a watched file changes" do
        expect(code_loader).to receive(:reload).once

        tick
        touch(daemon_file)
        tick
        tick
      end

      it "ignores changes to other files" do
        expect(code_loader).not_to receive(:reload)

        touch("#{app_path}/test_controller.rb")
        tick
      end

      it "reloads the code when a watched file is deleted" do
        expect(code_loader).to receive(:reload).once

        File.unlink(daemon_file)
        tick
      end

      it "syncs the request-time change tracking after a successful reload" do
        allow(code_loader).to receive(:reload)

        touch(daemon_file)
        tick

        expect(code_loader.check_updated!).to be(false)
      end

      it "picks up the new list of watched files after a reload" do
        allow(code_loader).to receive(:reload) { watched_files << "#{app_path}/application_daemon.rb" }

        touch(daemon_file)
        tick
        tick

        expect(code_loader).to have_received(:reload).once
      end

      it "doesn't start a reload while another one is in progress" do
        code_loader.instance_variable_set(:@reload_in_progress, true)
        expect(code_loader).not_to receive(:reload)

        touch(daemon_file)
        tick
      end

      context "when the reload fails" do
        before do
          allow(code_loader).to receive(:reload).and_raise(SyntaxError, "routes.rb: unexpected end-of-input")
          touch(daemon_file)
          tick
        end

        it "logs the error" do
          expect(logger).to have_received(:error).with(/Failed to reload code: SyntaxError/)
        end

        it "lets the next request retry the reload" do
          expect(code_loader.check_updated!).to be(true)
          expect(code_loader.check_updated!).to be(false)
        end

        it "doesn't retry the reload in the background until the files change again" do
          tick
          tick
          expect(code_loader).to have_received(:reload).once

          touch(daemon_file)
          tick
          expect(code_loader).to have_received(:reload).twice
        end
      end
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

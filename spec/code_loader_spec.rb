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
end

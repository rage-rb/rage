# frozen_string_literal: true

require "rage/cli"
require "tmpdir"

RSpec.describe CLISkills do
  subject(:skills_cli) { described_class.new }

  let(:manifest) do
    { "versions" => { "1.0" => "v1.0.0", "1.1" => "v1.1.0" } }
  end

  let(:tarball_content) { create_mock_tarball }
  let(:checksum) { "#{Digest::SHA256.hexdigest(tarball_content)}  skills.tar.gz" }

  before do
    stub_const("Rage::VERSION", "1.1.0")
    allow(skills_cli).to receive(:fetch).and_call_original
    allow(skills_cli).to receive(:fetch).with("https://rage-rb.github.io/skills/manifest.json").and_return(manifest.to_json)
    allow(skills_cli).to receive(:fetch).with(%r{/releases/download/.*/skills\.tar\.gz}).and_return(tarball_content)
    allow(skills_cli).to receive(:fetch).with(%r{/releases/download/.*/checksums\.txt}).and_return(checksum)
  end

  describe "#install" do
    subject { skills_cli.install }

    around(:example) do |example|
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) { example.run }
      end
    end

    before do
      allow(skills_cli).to receive(:choose_installation_path).and_return(".claude/skills/rage-framework")
    end

    it "installs skills to the chosen path" do
      expect(skills_cli).to receive(:say).with("Downloading skills...")
      expect(skills_cli).to receive(:say).with(/Installed Rage skills v1\.1\.0/)
      expect(skills_cli).to receive(:say).with("Skills are now available to your coding agent.")

      subject

      expect(File).to exist(".claude/skills/rage-framework/.version")
      expect(File.read(".claude/skills/rage-framework/.version")).to eq("v1.1.0")
    end

    context "when user cancels installation" do
      before do
        allow(skills_cli).to receive(:choose_installation_path).and_return(nil)
      end

      it "does not install anything" do
        expect(skills_cli).not_to receive(:fetch_skills_version)

        subject
      end
    end

    context "when manifest fetch fails" do
      before do
        allow(skills_cli).to receive(:fetch).with("https://rage-rb.github.io/skills/manifest.json").and_return(nil)
      end

      it "displays an error" do
        expect(skills_cli).to receive(:say_error) do |error|
          expect(error.message).to include("Could not download skills manifest")
        end

        subject
      end
    end

    context "when checksum verification fails" do
      let(:checksum) { "invalid_checksum  skills.tar.gz" }

      before do
        allow(skills_cli).to receive(:say)
      end

      it "displays an error" do
        expect(skills_cli).to receive(:say_error) do |error|
          expect(error.message).to include("Download verification failed")
        end

        subject
      end
    end

    context "when no skills available for current Rage version" do
      before do
        stub_const("Rage::VERSION", "2.0.0")
      end

      it "displays an error" do
        expect(skills_cli).to receive(:say_error) do |error|
          expect(error.message).to include("No skills available for Rage 2.x")
        end

        subject
      end
    end
  end

  describe "#update" do
    subject { skills_cli.update }

    around(:example) do |example|
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) { example.run }
      end
    end

    context "when no existing installation found" do
      it "runs fresh install" do
        expect(skills_cli).to receive(:say).with("No existing installation found. Running fresh install...\n\n")
        expect(skills_cli).to receive(:install)

        subject
      end
    end

    context "when existing installation is up to date" do
      before do
        FileUtils.mkdir_p(".claude/skills/rage-framework")
        File.write(".claude/skills/rage-framework/.version", "v1.1.0")
      end

      it "reports already up to date" do
        expect(skills_cli).to receive(:say).with(".claude/skills/rage-framework: already up to date.")

        subject
      end
    end

    context "when existing installation needs update" do
      before do
        FileUtils.mkdir_p(".claude/skills/rage-framework")
        File.write(".claude/skills/rage-framework/.version", "v1.0.0")
      end

      it "updates the installation" do
        expect(skills_cli).to receive(:say).with("Updating .claude/skills/rage-framework...")
        expect(skills_cli).to receive(:say).with(/Updated 1 installation to v1\.1\.0/)

        subject

        expect(File.read(".claude/skills/rage-framework/.version")).to eq("v1.1.0")
      end

      it "removes stale files from previous installation" do
        File.write(".claude/skills/rage-framework/old_file.txt", "stale content")
        allow(skills_cli).to receive(:say)

        subject

        expect(File).not_to exist(".claude/skills/rage-framework/old_file.txt")
      end
    end

    context "when multiple installations exist" do
      before do
        FileUtils.mkdir_p(".claude/skills/rage-framework")
        FileUtils.mkdir_p(".cursor/skills/rage-framework")
        File.write(".claude/skills/rage-framework/.version", "v1.0.0")
        File.write(".cursor/skills/rage-framework/.version", "v1.0.0")
      end

      it "updates all installations" do
        expect(skills_cli).to receive(:say).with("Updating .claude/skills/rage-framework...")
        expect(skills_cli).to receive(:say).with("Updating .cursor/skills/rage-framework...")
        expect(skills_cli).to receive(:say).with(/Updated 2 installations to v1\.1\.0/)

        subject
      end
    end

    context "with --json flag" do
      let(:skills_cli) { described_class.new([], json: true) }

      before do
        FileUtils.mkdir_p(".claude/skills/rage-framework")
        File.write(".claude/skills/rage-framework/.version", "v1.0.0")
      end

      it "outputs JSON to stdout" do
        output = capture_stdout { subject }
        result = JSON.parse(output)

        expect(result["status"]).to eq("updated")
        expect(result["version"]).to eq("v1.1.0")
        expect(result["paths"]).to include(".claude/skills/rage-framework")
      end

      it "outputs human-readable messages to stderr" do
        expect { subject }.to output(/Updating/).to_stderr
      end

      context "when already up to date" do
        before do
          File.write(".claude/skills/rage-framework/.version", "v1.1.0")
        end

        it "outputs up_to_date status" do
          output = capture_stdout { subject }
          result = JSON.parse(output)

          expect(result["status"]).to eq("up_to_date")
          expect(result["version"]).to eq("v1.1.0")
        end
      end

      context "when an error occurs" do
        before do
          allow(skills_cli).to receive(:fetch).with("https://rage-rb.github.io/skills/manifest.json").and_return(nil)
        end

        it "outputs error status and exits with code 1" do
          original_stdout = $stdout
          $stdout = StringIO.new

          expect { subject }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }

          output = $stdout.string
          $stdout = original_stdout

          result = JSON.parse(output)
          expect(result["status"]).to eq("error")
          expect(result["message"]).to include("Could not download")
        end
      end
    end
  end

  describe "#choose_installation_path" do
    subject { skills_cli.choose_installation_path }

    before do
      allow(skills_cli).to receive(:print_table)
      allow(skills_cli).to receive(:say)
      allow(skills_cli).to receive(:set_color) { |text, _| text }
    end

    context "when user selects Claude Code" do
      before do
        allow(skills_cli).to receive(:ask).with(/Select your coding agent/, default: "1").and_return("1")
        allow(skills_cli).to receive(:ask).with(/Proceed with installation/, default: "y").and_return("y")
      end

      it "returns Claude Code path" do
        expect(subject).to eq(".claude/skills/rage-framework")
      end
    end

    context "when user selects Cursor" do
      before do
        allow(skills_cli).to receive(:ask).with(/Select your coding agent/, default: "1").and_return("3")
        allow(skills_cli).to receive(:ask).with(/Proceed with installation/, default: "y").and_return("y")
      end

      it "returns Cursor path" do
        expect(subject).to eq(".cursor/skills/rage-framework")
      end
    end

    context "when user types agent name" do
      before do
        allow(skills_cli).to receive(:ask).with(/Select your coding agent/, default: "1").and_return("cursor")
        allow(skills_cli).to receive(:ask).with(/Proceed with installation/, default: "y").and_return("y")
      end

      it "matches by name" do
        expect(subject).to eq(".cursor/skills/rage-framework")
      end
    end

    context "when user cancels" do
      before do
        allow(skills_cli).to receive(:ask).with(/Select your coding agent/, default: "1").and_return("1")
        allow(skills_cli).to receive(:ask).with(/Proceed with installation/, default: "y").and_return("n")
      end

      it "returns nil" do
        expect(skills_cli).to receive(:say).with("Installation cancelled.")

        expect(subject).to be_nil
      end
    end
  end

  describe "#fetch_skills_version" do
    subject { skills_cli.send(:fetch_skills_version) }

    context "when exact minor version match exists" do
      let(:manifest) do
        { "versions" => { "1.0" => "v1.0.0", "1.1" => "v1.1.0" } }
      end

      it "returns the matching version" do
        expect(subject).to eq("v1.1.0")
      end
    end

    context "when only lower minor version exists" do
      let(:manifest) do
        { "versions" => { "1.0" => "v1.0.5" } }
      end

      it "returns the highest compatible version" do
        expect(subject).to eq("v1.0.5")
      end
    end

    context "when higher minor version exists" do
      let(:manifest) do
        { "versions" => { "1.0" => "v1.0.0", "1.2" => "v1.2.0" } }
      end

      it "returns the lower version" do
        expect(subject).to eq("v1.0.0")
      end
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def create_mock_tarball
    require "zlib"
    require "rubygems/package"
    require "stringio"

    tar_io = StringIO.new
    tar_io.set_encoding("ASCII-8BIT")

    Gem::Package::TarWriter.new(tar_io) do |tar|
      tar.add_file("README.md", 0o644) { |f| f.write("# Skills") }
    end

    gz_io = StringIO.new
    gz_io.set_encoding("ASCII-8BIT")

    Zlib::GzipWriter.wrap(gz_io) do |gz|
      gz.write(tar_io.string)
    end

    gz_io.string
  end
end

# frozen_string_literal: true

RSpec.describe Rage::UploadedFile do
  let(:file_path) { File.join(Dir.tmpdir, "rage_uploaded_file_test_#{Process.pid}") }

  let(:file) do
    File.write(file_path, "test file content")
    File.open(file_path, "r+")
  end

  let(:original_filename) { "document.pdf" }
  let(:content_type) { "application/pdf" }

  subject(:uploaded_file) { described_class.new(file, original_filename, content_type) }

  after do
    file.close unless file.closed?
    File.delete(file_path) if File.exist?(file_path)
  end

  describe "#initialize" do
    it "stores the file" do
      expect(uploaded_file.file).to eq(file)
    end

    it "stores the original filename" do
      expect(uploaded_file.original_filename).to eq("document.pdf")
    end

    it "stores the content type" do
      expect(uploaded_file.content_type).to eq("application/pdf")
    end
  end

  describe "#file" do
    it "returns the underlying file object" do
      expect(uploaded_file.file).to be(file)
    end
  end

  describe "#tempfile" do
    it "is an alias for #file" do
      expect(uploaded_file.tempfile).to be(uploaded_file.file)
    end
  end

  describe "#read" do
    it "reads the entire file content" do
      expect(uploaded_file.read).to eq("test file content")
    end

    context "with length argument" do
      it "reads the specified number of bytes" do
        expect(uploaded_file.read(4)).to eq("test")
      end
    end

    context "with length and buffer arguments" do
      it "reads into the provided buffer" do
        buffer = String.new
        uploaded_file.read(4, buffer)
        expect(buffer).to eq("test")
      end
    end
  end

  describe "#close" do
    it "closes the underlying file" do
      uploaded_file.close
      expect(file.closed?).to be(true)
    end
  end

  describe "#path" do
    it "returns the path of the underlying file" do
      expect(uploaded_file.path).to eq(file.path)
    end
  end

  describe "#to_path" do
    it "returns the path of the underlying file" do
      expect(uploaded_file.to_path).to eq(file.to_path)
    end
  end

  describe "#rewind" do
    it "rewinds the underlying file" do
      uploaded_file.read
      expect(uploaded_file.eof?).to be(true)

      uploaded_file.rewind

      expect(uploaded_file.eof?).to be(false)
      expect(uploaded_file.read).to eq("test file content")
    end
  end

  describe "#size" do
    it "returns the size of the file" do
      expect(uploaded_file.size).to eq(17) # "test file content".length
    end
  end

  describe "#eof?" do
    it "returns false when not at end of file" do
      expect(uploaded_file.eof?).to be(false)
    end

    it "returns true when at end of file" do
      uploaded_file.read
      expect(uploaded_file.eof?).to be(true)
    end
  end

  describe "#to_io" do
    it "returns the IO object" do
      expect(uploaded_file.to_io).to eq(file.to_io)
    end
  end

  describe "with different content types" do
    let(:content_type) { "image/png" }
    let(:original_filename) { "photo.png" }

    it "handles image files" do
      expect(uploaded_file.content_type).to eq("image/png")
      expect(uploaded_file.original_filename).to eq("photo.png")
    end
  end

  describe "with nil content type" do
    let(:content_type) { nil }

    it "allows nil content type" do
      expect(uploaded_file.content_type).to be_nil
    end
  end
end

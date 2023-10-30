# frozen_string_literal: true

##
# Models uploaded files.
#
# The actual file is accessible via the `file` accessor, though some
# of its interface is available directly for convenience.
#
# Rage will automatically unlink the files, so there is no need to clean them with a separate maintenance task.
class Rage::UploadedFile
  # The basename of the file in the client.
  attr_reader :original_filename

  # A string with the MIME type of the file.
  attr_reader :content_type

  # A `File` object with the actual uploaded file. Note that some of its interface is available directly.
  attr_reader :file
  alias_method :tempfile, :file

  def initialize(file, original_filename, content_type)
    @file = file
    @original_filename = original_filename
    @content_type = content_type
  end

  # Shortcut for `file.read`.
  def read(length = nil, buffer = nil)
    @file.read(length, buffer)
  end

  # Shortcut for `file.open`.
  def open
    @file.open
  end

  # Shortcut for `file.close`.
  def close(unlink_now = false)
    @file.close(unlink_now)
  end

  # Shortcut for `file.path`.
  def path
    @file.path
  end

  # Shortcut for `file.to_path`.
  def to_path
    @file.to_path
  end

  # Shortcut for `file.rewind`.
  def rewind
    @file.rewind
  end

  # Shortcut for `file.size`.
  def size
    @file.size
  end

  # Shortcut for `file.eof?`.
  def eof?
    @file.eof?
  end

  def to_io
    @file.to_io
  end
end

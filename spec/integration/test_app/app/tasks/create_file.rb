class CreateFile
  include Rage::Deferred::Task

  def perform(file_path, file_mode, content:)
    sleep 0.5

    file = File.open(file_path, file_mode)
    file.write(content)
    file.close
  end
end

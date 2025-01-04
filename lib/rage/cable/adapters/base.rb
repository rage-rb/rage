# frozen_string_literal: true

class Rage::Cable::Adapters::Base
  def pick_a_worker(&block)
    _lock, lock_path = Tempfile.new.yield_self { |file| [file, file.path] }

    Iodine.on_state(:on_start) do
      if File.new(lock_path).flock(File::LOCK_EX | File::LOCK_NB)
        if Rage.logger.debug?
          puts "INFO: #{Process.pid} is managing #{self.class.name.split("::").last} subscriptions."
        end
        block.call
      end
    end
  end
end

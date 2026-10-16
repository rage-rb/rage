class SleepDaemon < Rage::Daemon
  def perform
    @pid = Process.spawn("sleep 60", pgroup: true)
    Process.wait(@pid)
  end

  def cleanup
    Process.kill("TERM", @pid)
    Rage.logger.info "cleanup done"
  end
end

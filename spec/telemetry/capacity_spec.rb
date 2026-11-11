# frozen_string_literal: true

RSpec.describe Rage::Telemetry::Capacity do
  describe ".queued_connections" do
    before :all do
      skip("skipping queued_connections tests on Mac") if RUBY_PLATFORM =~ /darwin/
    end

    before do
      Fiber.set_scheduler(Rage::FiberScheduler.new)
    end

    after do
      Fiber.set_scheduler(nil)
    end

    it "reports the accept-queue depth of the server's listeners" do
      require "socket"

      s = TCPServer.new("127.0.0.1", 0)
      port = s.addr[1]
      s.close
      result = nil

      Iodine.workers = 1
      Iodine.on_state(:on_start) do
        Iodine.listen(port: port, handler: -> { [200, {}, ["ok"]] })
        socks = 5.times.map { TCPSocket.new("127.0.0.1", port) }
        Iodine.run { result = described_class.queued_connections }
        socks.each(&:close)
        Iodine.run { Iodine.stop }
      end
      Iodine.start

      expect(result).to eq(5)
    end

    it "is callable from within the reactor via .every" do
      require "socket"

      s = TCPServer.new("127.0.0.1", 0)
      port = s.addr[1]
      s.close
      result = nil

      Iodine.workers = 1
      Iodine.on_state(:on_start) do
        Iodine.listen(port: port, handler: -> { [200, {}, ["ok"]] })
        Rage::Telemetry.every(5) do
          Iodine.run { result = described_class.queued_connections }
          Iodine.stop
        end
        Iodine.run_after(200) { Iodine.stop }
      end
      Iodine.start

      expect(result).to be_a(Integer)
    end
  end

  describe ".event_loop_utilization" do
    def rage_lib
      File.expand_path("../../lib", __dir__)
    end

    def iodine_lib
      File.join(Gem.loaded_specs.fetch("rage-iodine").full_gem_path, "lib")
    end

    # Fresh process per server example: state callbacks persist across the
    # whole rspec process, and a stale one could stop a later server. The
    # server writes its result to ELU_OUT_PATH; output is captured for
    # failure reports.
    def fresh_capacity_server(pre_task_code, task_code)
      callback_code = <<~RUBY
        require "iodine"
        require "#{File.join(rage_lib, "rage/telemetry/capacity.rb")}"
        Iodine.workers = 2
        Rage::Telemetry::Capacity.enable_event_loop_utilization!
        #{pre_task_code}
        Iodine.on_state(:on_start) do
          #{task_code}
        end
        Iodine.start
      RUBY
      out_path = File.join(Dir.tmpdir, "rage-elu-#{Process.pid}-#{rand(1e9)}.txt")
      output = IO.popen(
        [{ "ELU_OUT_PATH" => out_path }, RbConfig.ruby, "-I#{rage_lib}", "-I#{iodine_lib}", "-e", callback_code],
        err: [:child, :out],
        &:read
      )
      raise "capacity server run failed:\n#{output}" unless File.exist?(out_path)
      File.read(out_path)
    ensure
      File.delete(out_path) if out_path && File.exist?(out_path)
    end

    it "returns nil when event loop utilization tracking is off" do
      capacity_file = File.join(rage_lib, "rage/telemetry/capacity.rb")
      out = IO.popen([RbConfig.ruby, "-I#{rage_lib}", "-I#{iodine_lib}", "-e",
        "require \"iodine\"\nrequire \"#{capacity_file}\"\n" \
        "p Rage::Telemetry::Capacity.event_loop_utilization"], &:read).strip

      expect(out).to eq("nil")
    end

    it "starts a clean window in forked workers and reports a busy loop while the reactor blocks" do
      base, blocked = fresh_capacity_server(<<~PRE, <<~TASK).split.map(&:to_f)
        sleep 0.6
      PRE
        base = Rage::Telemetry::Capacity.event_loop_utilization
        Iodine.run do
          # Block the reactor: that time is active, not event provider idle.
          sleep 0.3
          blocked = Rage::Telemetry::Capacity.event_loop_utilization
          File.write(ENV.fetch("ELU_OUT_PATH"), [base, blocked].map(&:to_s).join(" "))
          # we run inside a worker: ask the root process to shut the server
          # down (Iodine.stop from a worker would just respawn it).
          Process.kill("SIGINT", Process.ppid)
        end
      TASK

      # The parent aged its own window before forking: the worker must open
      # a fresh one (0.0 baseline) rather than comparing its restarted
      # counters against the inherited sample point (~1.0).
      expect(base).to eq(0.0)
      expect(blocked).to be_a(Float)
      expect(blocked).to be > 0.6
    end
  end
end

# frozen_string_literal: true

RSpec.describe Rage::Telemetry::Capacity do
  describe ".queued_connections" do
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
end

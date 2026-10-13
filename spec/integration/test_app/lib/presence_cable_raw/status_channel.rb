module PresenceCableRaw
  class StatusChannel < Rage::Cable::Channel
    def subscribed
      stream_from "presence"
      transmit "ok"
    end

    def unsubscribed
      stop_stream_from "presence"
    end
  end
end

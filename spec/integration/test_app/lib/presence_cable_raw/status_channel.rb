module PresenceCableRaw
  class StatusChannel < Rage::Cable::Channel
    def subscribed
      stream_from "presence"
    end

    def unsubscribed
      stop_stream_from "presence"
    end
  end
end

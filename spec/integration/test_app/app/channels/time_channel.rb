class TimeChannel < RageCable::Channel
  def subscribed
    stream_from "current_time"
    transmit({ sending_current_time: Time.now.to_i })
  end

  def what_time_is_it
    transmit({ transmitting_current_time: Time.now.to_i })
  end

  def sync_time
    broadcast("current_time", { broadcasting_current_time: Time.now.to_i, message: "initiated by user #{current_user}" })
  end

  def remote_sync_time(data)
    sleep 1
    transmit({ message: "synced from #{data["remote"]}" })
  end
end

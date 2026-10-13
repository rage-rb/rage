class LogsChannel < RageCable::Channel
  def subscribed
    Rage.logger.info "client subscribed"
    transmit "ok"
  end

  def receive(data)
    Rage.logger.with_context(content: data["message"]) do
      Rage.logger.info "message received"
    end

    transmit "ok"
  end
end

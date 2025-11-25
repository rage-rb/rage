class LogsChannel < RageCable::Channel
  def subscribed
    Rage.logger.info "client subscribed"
  end

  def receive(data)
    Rage.logger.with_context(content: data["message"]) do
      Rage.logger.info "message received"
    end
  end
end

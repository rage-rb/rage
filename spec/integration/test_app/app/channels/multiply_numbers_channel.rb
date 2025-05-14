class MultiplyNumbersChannel < RageCable::Channel
  def subscribed
    reject unless params[:multiplier]
  end

  def receive(data)
    transmit({ result: data["i"].to_i * params[:multiplier].to_i })
  end
end

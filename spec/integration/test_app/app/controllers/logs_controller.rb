class LogsController < RageController::API
  def custom
    Rage.logger.info "log_1"
    Rage.logger.debug "can't see me"

    Rage.logger.tagged("tag_2") do
      Rage.logger.warn "log_2"
    end

    sleep 0.1

    Rage.logger.with_context(test: true) do
      Rage.logger.error "log_3"
    end
  end

  def fiber
    Rage.logger.info "outside_1"

    f = Fiber.schedule do
      sleep 0.1
      Rage.logger.tagged("in_fiber") do
        Rage.logger.info "inside"
      end
    end
    Fiber.await f

    Rage.logger.info "outside_2"
  end

  private

  def append_info_to_payload(payload)
    if params[:append_info_to_payload]
      payload["hello"] = "world"
    end
  end
end

class ApplicationController < RageController::API
  if Rage.env.development? || Rage.env.test?
    before_action do
      Rage.logger.with_context(params: params) { Rage.logger.debug("parameters") }
    end
  end
end

module Api
  class BaseController < RageController::API
    # @version 2.0.0
    # @title My Test API
    # @auth authenticate_user

    before_action :authenticate_user

    private

    def authenticate_user
    end
  end
end

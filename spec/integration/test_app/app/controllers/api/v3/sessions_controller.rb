module Api
  module V3
    # @auth authenticate_by_token #/components/securitySchemes/ApiKeyAuth
    class SessionsController < RageController::API
      before_action :authenticate_by_token

      # Returns the current session.
      def show
      end

      private

      def authenticate_by_token
      end
    end
  end
end

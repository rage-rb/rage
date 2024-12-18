module Api
  module V2
    class UsersController < BaseController
      skip_before_action :authenticate_user, only: :index

      # Returns the list of all users.
      # @description Test description.
      # @response Array<UserResource>
      def index
      end

      # Returns a specific user.
      # @response UserResource
      # @deprecated
      def show
      end

      # @private
      # Creates a user.
      def create
      end
    end
  end
end

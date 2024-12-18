module Api
  module V1
    class UsersController < BaseController
      # Returns the list of all users.
      # @description Test
      #   description
      #   for
      #   the
      #   method.
      # @response [UserResource]
      def index
      end

      # Returns a specific user.
      # @response ::UserResource
      # @response 404
      def show
      end

      # Creates a user.
      # @request { user: { name: String, email: String, password: String } }
      # @response Api::V1::UserResource
      def create
      end
    end
  end
end

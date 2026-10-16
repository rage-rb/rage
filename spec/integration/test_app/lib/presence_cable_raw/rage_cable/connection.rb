module PresenceCableRaw
  module RageCable
    class Connection < Rage::Cable::Connection
      include Rage::Cable::RemoteDisconnect

      identified_by :current_user, :current_account, :current_user__account

      def connect
        self.current_user = params[:user_id]
        self.current_account = params[:account_id]

        return reject_unauthorized_connection if current_user.nil? && current_account.nil?

        if current_user && current_account
          self.current_user__account = [current_user, current_account]
        end
      end
    end
  end
end

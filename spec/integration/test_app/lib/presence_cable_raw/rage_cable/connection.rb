module PresenceCableRaw
  module RageCable
    class Connection < Rage::Cable::Connection
      identified_by :current_account

      def connect
        account_id = params[:account_id]

        if account_id
          self.current_account = account_id
        else
          reject_unauthorized_connection
        end
      end
    end
  end
end

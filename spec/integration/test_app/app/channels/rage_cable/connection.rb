module RageCable
  class Connection < Rage::Cable::Connection
    identified_by :current_user

    def connect
      user_id = params[:user_id]

      if user_id
        self.current_user = user_id
      else
        reject_unauthorized_connection
      end
    end
  end
end

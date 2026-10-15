class CableController < RageController::API
  def close
    RageCable::Connection.disconnect(current_user: params[:user_id])
    head :ok
  end

  def close_raw
    user_id, account_id = params[:user_id], params[:account_id]

    identifier = if user_id && account_id
      { current_user__account: [user_id, account_id] }
    elsif user_id
      { current_user: user_id }
    elsif account_id
      { current_account: account_id }
    end

    if identifier
      PresenceCableRaw::RageCable::Connection.disconnect(**identifier)
      head :ok
    else
      head :bad_request
    end
  end
end

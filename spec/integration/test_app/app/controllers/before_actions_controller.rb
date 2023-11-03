class BeforeActionsController < RageController::API
  before_action :create_message
  before_action :create_timestamp, if: -> { params[:with_timestamp] }

  def get
    response = { message: @message }
    response[:timestamp] = @timestamp if @timestamp

    render json: response
  end

  private

  def create_message
    @message = "hello world"
  end

  def create_timestamp
    @timestamp = 1636466868
  end
end

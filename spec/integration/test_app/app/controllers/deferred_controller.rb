class DeferredController < RageController::API
  def create
    CreateFile.enqueue(params[:file_path])
    head :ok
  end
end

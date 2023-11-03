class ApplicationController < RageController::API
  def get
    render plain: "i am a get response"
  end

  def post
    render plain: "i am a post response"
  end

  def put
    render plain: "i am a put response"
  end

  def patch
    render plain: "i am a patch response"
  end

  def delete
    render plain: "i am a delete response"
  end

  def empty
  end

  def raise_error
    raise "1155 test error"
  end
end

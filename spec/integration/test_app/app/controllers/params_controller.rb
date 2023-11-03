require "yaml"
require "digest"

class ParamsController < RageController::API
  def digest
    render plain: Digest::MD5.hexdigest(params.to_yaml)
  end

  def multipart
    params_with_digest = params.merge(text_digest: Digest::MD5.hexdigest(params[:text].read))
    render plain: Digest::MD5.hexdigest(params_with_digest.to_yaml)
  end
end

module Api
  module V1
    class AvatarResource
      include Alba::Resource
      attributes :url, :updated_at
    end
  end
end

module Api
  module V1
    class UserResource < BaseUserResource
      include Alba::Resource

      attributes :id, :name
      has_one :avatar

      nested_attribute :address do
        attributes :city, :zip, :country
      end
    end
  end
end

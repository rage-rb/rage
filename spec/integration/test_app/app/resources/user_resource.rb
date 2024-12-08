class UserResource
  include Alba::Resource

  attributes :full_name
  has_many :comments
end

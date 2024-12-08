class BaseUserResource
  include Alba::Resource
  root_key :user, :users
  attributes :email
end

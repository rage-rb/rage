Rage.routes.draw do
  root to: ->(env) { [200, {}, "It works!"] }

  get "get", to: "application#get"
  post "post", to: "application#post"
  put "put", to: "application#put"
  patch "patch", to: "application#patch"
  delete "delete", to: "application#delete"
  get "empty", to: "application#empty"
  get "raise_error", to: "application#raise_error"
  get "get_request_id", to: "application#get_request_id"
  get "get_action_name", to: "application#get_action_name_action"
  get "get_route_uri_pattern/:id", to: "application#get_route_uri_pattern"

  get "params/digest", to: "params#digest"
  post "params/digest", to: "params#digest"
  get "params/:id/defaults", to: "params#digest", defaults: { hello: "world" }
  post "params/multipart", to: "params#multipart"

  get "async/sum", to: "async#sum"
  get "async/long", to: "async#long"
  get "async/empty", to: "async#empty"
  get "async/raise_error", to: "async#raise_error"
  get "async/short_sleep", to: "async#short_sleep"

  get "before_actions/get", to: "before_actions#get"

  get "logs/custom", to: "logs#custom"
  get "logs/fiber", to: "logs#fiber"

  get "reload/verify", to: "reload#verify"

  post "deferred/create_file", to: "deferred#create"

  mount ->(_) { [200, {}, ""] }, at: "/admin"

  namespace :api do
    namespace :v1 do
      resources :users, only: %i(index show create)
    end

    namespace :v2 do
      resources :users, only: %i(index show create)
    end

    namespace :v3 do
      resources :users, only: :show
    end
  end
end

Rage.routes.draw do
  root to: ->(env) { [200, {}, "It works!"] }

  get "get", to: "application#get"
  post "post", to: "application#post"
  put "put", to: "application#put"
  patch "patch", to: "application#patch"
  delete "delete", to: "application#delete"
  get "empty", to: "application#empty"
  get "raise_error", to: "application#raise_error"

  get "params/digest", to: "params#digest"
  post "params/digest", to: "params#digest"
  get "params/:id/defaults", to: "params#digest", defaults: { hello: "world" }
  post "params/multipart", to: "params#multipart"

  get "async/sum", to: "async#sum"
  get "async/long", to: "async#long"
  get "async/empty", to: "async#empty"

  get "before_actions/get", to: "before_actions#get"

  get "logs/custom", to: "logs#custom"
  get "logs/fiber", to: "logs#fiber"
end

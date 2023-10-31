Rage.routes.draw do
  root to: ->(env) { [200, {}, "It works!"] }

  get "get", to: "application#get"
  post "post", to: "application#post"
  put "put", to: "application#put"
  patch "patch", to: "application#patch"
  delete "delete", to: "application#delete"
  get "empty", to: "application#empty"
  get "raise_error", to: "application#raise_error"

  get "params/query", to: "params#query"
  get "params/:id/defaults", to: "params#defaults", defaults: { hello: "world" }
  post "params/json", to: "params#json"
  post "params/multipart", to: "params#multipart"
  post "params/urlencoded", to: "params#urlencoded"

  get "async/sum", to: "async#sum"
  get "async/long", to: "async#long"

  get "before_actions/get", to: "before_actions#get"
end

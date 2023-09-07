This is an almost complete rewrite of https://github.com/delvedor/find-my-way.

Currrently, the only constraint supported is the `host` constraint. Regexp constraints are likely to be added. Custom/lambda constraints are unlikely to be added.

Compared to the Rails router, the most notable difference except constraints is that a wildcard segment can only be in the last section of the path and cannot be named.

```ruby
Rage.routes.draw do
  get "photos/:id", to: "photos#show", constraints: { host: /myhost/ }

  scope path: "api/v1", module: "api/v1" do
    get "photos/:id", to: "photos#show"
  end

  root to: "photos#index"

  get "*", to: ->(env) { [404, {}, [{ message: "Not Found" }.to_json]] }
end
```

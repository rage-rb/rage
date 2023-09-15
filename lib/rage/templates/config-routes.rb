Rage.routes.draw do
  root to: ->(env) { [200, {}, "It works!"] }
end

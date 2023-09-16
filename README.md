# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)

Inspired by [Deno](https://deno.com) and built on top of [Iodine](https://github.com/rage-rb/iodine), this is a Ruby web framework that is based on the following design principles:

* **Rails compatible API** - Rails' API is clean, straightforward, and simply makes sense. I believe it was one of the reasons why Rails was so successful in the past.

* **High performance** - some think performance is not a major metric for a framework, but I don't believe it's true. Poor performance is a risk, and in today's world, companies refuse to use risky technologies.

* **API-only** - the only technology we should be using to create web UI is JavaScript. I recommend checking out [Vite](https://vitejs.dev) if you don't know where to start.

* **Acceptance of modern Ruby** - the framework includes a fiber scheduler, which means your code never blocks while waiting on IO.

This framework results from reflecting on [Ruby's declining popularity](https://survey.stackoverflow.co/2023/#most-popular-technologies-language) and attempting to answer why this is happening and what we, as a community, could be doing differently.

## Installation

Install the gem:
```
$ gem install rage-rb
```

Create a new app:
```
$ rage new my_app
```

Switch to your new application and install dependencies:
```
$ cd my_app
$ bundle
```

Start up the server and visit http://localhost:3000.
```
$ rage s
```

Start coding!

## Benchmarks

#### hello world

```ruby
class ArticlesController < ApplicationController
  def index
    render json: { hello: "world" }
  end
end
```
![Requests per second](https://github.com/rage-rb/rage/assets/2270393/7d9f408c-7cec-4cc0-a509-66c9dedc1d0a)

#### waiting on IO

```ruby
require "net/http"

class ArticlesController < ApplicationController
  def index
    Net::HTTP.get(URI("<endpoint-that-responds-in-one-second>"))
    head :ok
  end
end
```
![Time to complete 100 requests](https://github.com/rage-rb/rage/assets/2270393/007044e9-efe0-4675-9cab-8a4868154118)

## Upcoming releases

Version | Changes
------- |------------
0.2 | Gem configuration by env.<br>Add `skip_before_action`.<br>Add `rescue_from`.<br>Router updates:<br>&emsp;• make the `root` helper work correctly with `scope`;<br>&emsp;• support the `defaults` option;
0.3 | CLI updates:<br>&emsp;• `routes` task;<br>&emsp;• `console` task;<br>Support the `:if` and `:unless` options in `before_action`.<br>Allow to set response headers.
0.4 | Expose the `params` object.<br>Support header authentication with `authenticate_with_http_token`.<br>Router updates:<br>&emsp;• add the `resources` route helper;<br>&emsp;• add the `namespace` route helper;<br>&emsp;• support regexp constraints;
0.5 | Implement Iodine-based equivalent of `ActionController::Live`.<br>Use `ActionDispatch::RemoteIp`.
0.6 | Expose the `cookies` object.<br>Expose the `send_data` and `send_file` methods.<br>Support conditional get with `etag` and `last_modified`.
0.7 | Add request logging.
0.8 | Collect app metrics.
0.9 | Automatic code reloading in development.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rage-rb/rage. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

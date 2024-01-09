<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.1%2B-%23f40000)


Inspired by [Deno](https://deno.com) and built on top of [Iodine](https://github.com/rage-rb/iodine), this is a Ruby web framework that is based on the following design principles:

* **Rails compatible API** - Rails' API is clean, straightforward, and simply makes sense. It was one of the reasons why Rails was so successful in the past.

* **High performance** - some think performance is not a major metric for a framework, but it's not true. Poor performance is a risk, and in today's world, companies refuse to use risky technologies.

* **API-only** - separation of concerns is one of the most fundamental principles in software development. Backend and frontend are very different layers with different goals and paths to those goals. Separating BE code from FE code results in a much more sustainable architecture compared with classic Rails monoliths.

* **Acceptance of modern Ruby** - the framework includes a fiber scheduler, which means your code never blocks while waiting on IO.

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

## Getting Started

This gem is designed to be a drop-in replacement for Rails in API mode. Public API is mostly expected to match Rails, however, sometimes it's a little bit more strict.

Check out in-depth API docs for more information:

- [Controller API](https://rage-rb.pages.dev/RageController/API)
- [Routing API](https://rage-rb.pages.dev/Rage/Router/DSL/Handler)
- [Fiber API](https://rage-rb.pages.dev/Fiber)
- [Logger API](https://rage-rb.pages.dev/Rage/Logger)
- [Configuration API](https://rage-rb.pages.dev/Rage/Configuration)

Also, see the [changelog](https://github.com/rage-rb/rage/blob/master/CHANGELOG.md) and [upcoming-releases](https://github.com/rage-rb/rage#upcoming-releases) for currently supported and planned features.

### Example

A sample controller could look like this:

```ruby
require "net/http"

class PagesController < RageController::API
  rescue_from SocketError do |_|
    render json: { message: "error" }, status: 500
  end

  before_action :set_metadata

  def show
    page = Net::HTTP.get(URI("https://httpbin.org/json"))
    render json: { page: page, metadata: @metadata }
  end

  private

  def set_metadata
    @metadata = { format: "json", time: Time.now.to_i }
  end
end
```

Apart from `RageController::API` as a parent class, this is mostly a regular Rails controller. However, the main difference is under the hood - Rage runs every request in a separate fiber. During the call to `Net::HTTP.get`, the fiber is automatically paused, enabling the server to process other requests. Once the HTTP request is finished, the fiber will be resumed, potentially allowing to process hundreds of requests simultaneously.

To make this controller work, we would also need to update `config/routes.rb`. In this case, the file would look the following way:

```ruby
Rage.routes.draw do
  get "page", to: "pages#show"
end
```

:information_source: **Note**: Rage will automatically pause a fiber and continue to process other fibers on HTTP, PostgreSQL, and MySQL calls. Calls to `Thread.join` and `Ractor.join` will also automatically pause the current fiber.

Additionally, `Fiber.await` can be used to run several requests in parallel:

```ruby
require "net/http"

class PagesController < RageController::API
  def index
    pages = Fiber.await([
      Fiber.schedule { Net::HTTP.get(URI("https://httpbin.org/json")) },
      Fiber.schedule { Net::HTTP.get(URI("https://httpbin.org/html")) },
    ])

    render json: { pages: pages }
  end
end
```

:information_source: **Note**: When using `Fiber.await`, it is important to wrap any instance of IO into a fiber using `Fiber.schedule`.

## Benchmarks

#### hello world

```ruby
class ArticlesController < ApplicationController
  def index
    render json: { hello: "world" }
  end
end
```
![Requests per second](https://github.com/rage-rb/rage/assets/2270393/6c221903-e265-4c94-80e1-041f266c8f47)

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

Status | Changes
-- | ------------
:white_check_mark: | ~~Gem configuration by env.<br>Add `skip_before_action`.<br>Add `rescue_from`.<br>Router updates:<br>&emsp;• make the `root` helper work correctly with `scope`;<br>&emsp;• support the `defaults` option;~~
:white_check_mark: | ~~CLI updates:<br>&emsp;• `routes` task;<br>&emsp;• `console` task;<br>Support the `:if` and `:unless` options in `before_action`.<br>Allow to set response headers.~~
:white_check_mark: | ~~Expose the `params` object.<br>Support header authentication with `authenticate_with_http_token`.<br>Router updates:<br>&emsp;• add the `resources` route helper;<br>&emsp;• add the `namespace` route helper;~~
:white_check_mark:  | ~~Add request logging.~~
:white_check_mark: | ~~Automatic code reloading in development with Zeitwerk.~~
:white_check_mark: | ~~Support conditional get with `etag` and `last_modified`.~~
⏳ | Expose the `send_data` and `send_file` methods.
⏳ | Expose the `cookies` and `session` objects.
⏳ | Implement Iodine-based equivalent of Action Cable.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rage-rb/rage. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.1%2B-%23f40000)

Rage is a high-performance framework compatible with Rails, featuring [WebSocket](https://github.com/rage-rb/rage/wiki/WebSockets-guide) support and automatic generation of [OpenAPI](https://github.com/rage-rb/rage/wiki/OpenAPI-Guide) documentation for your APIs. The framework is built on top of [Iodine](https://github.com/rage-rb/iodine) and is based on the following design principles:

* **Rails compatible API** - Rails' API is clean, straightforward, and simply makes sense. It was one of the reasons why Rails was so successful in the past.

* **High performance** - some think performance is not a major metric for a framework, but it's not true. Poor performance is a risk, and in today's world, companies refuse to use risky technologies.

* **API-only** - separation of concerns is one of the most fundamental principles in software development. Backend and frontend are very different layers with different goals and paths to those goals. Separating BE code from FE code results in a much more sustainable architecture compared with classic Rails monoliths.

* **Acceptance of modern Ruby** - the framework includes a fiber scheduler, which means your code never blocks while waiting on I/O.

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

This gem is designed to be a drop-in replacement for Rails in API mode. Public API is expected to fully match Rails.

A Rage application can operate in two modes:

* **Rails Mode**: Integrate Rage into an existing Rails application to improve throughput and better handle traffic spikes. For more information, see [Rails Integration](https://github.com/rage-rb/rage/wiki/Rails-integration).
* **Standalone Mode**: Build high-performance services with minimal setup using Rage. To get started, run `rage new --help` for more details.

Check out in-depth API docs for more information:

- [Controller API](https://rage-rb.pages.dev/RageController/API)
- [Routing API](https://rage-rb.pages.dev/Rage/Router/DSL/Handler)
- [Fiber API](https://rage-rb.pages.dev/Fiber)
- [Logger API](https://rage-rb.pages.dev/Rage/Logger)
- [Configuration API](https://rage-rb.pages.dev/Rage/Configuration)

Built-in middleware:
- [CORS](https://rage-rb.pages.dev/Rage/Cors)
- [RequestId](https://rage-rb.pages.dev/Rage/RequestId)

Also, see the following integration guides:

- [Rails Integration](https://github.com/rage-rb/rage/wiki/Rails-integration)
- [RSpec Integration](https://github.com/rage-rb/rage/wiki/RSpec-integration)
- [WebSockets Guide](https://github.com/rage-rb/rage/wiki/WebSockets-guide)

If you are a first-time contributor, make sure to check the [overview doc](https://github.com/rage-rb/rage/blob/master/OVERVIEW.md) that shows how Rage's core components interact with each other.

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

:information_source: **Note**: When using `Fiber.await`, it is important to wrap every argument into a fiber using `Fiber.schedule`.

## Benchmarks

#### Hello World

```ruby
class BenchmarksController < ApplicationController
  def index
    render json: { hello: "world" }
  end
end
```

![Requests per second](https://github.com/user-attachments/assets/a7f864ae-0dfb-4628-a420-265a10d8591d)

#### Waiting on I/O

```ruby
require "net/http"

class BenchmarksController < ApplicationController
  def index
    Net::HTTP.get(URI("<endpoint-that-responds-in-one-second>"))
    head :ok
  end
end
```

![Time to complete 100 requests](https://github.com/user-attachments/assets/4f4feda3-bd88-43d8-8999-268534c2f9de)

#### Using ActiveRecord

```ruby
class BenchmarksController < ApplicationController
  def show
    render json: World.find(rand(1..10_000))
  end
end
```

![Requests per second](https://github.com/user-attachments/assets/04678788-0034-4db4-9582-d0bc16fd9e28)

## Upcoming releases

Status | Changes
-- | ------------
:white_check_mark: | ~~Gem configuration by env.<br>Add `skip_before_action`.<br>Add `rescue_from`.<br>Router updates:<br>&emsp;• make the `root` helper work correctly with `scope`;<br>&emsp;• support the `defaults` option;~~
:white_check_mark: | ~~CLI updates:<br>&emsp;• `routes` task;<br>&emsp;• `console` task;<br>Support the `:if` and `:unless` options in `before_action`.<br>Allow to set response headers.~~
:white_check_mark: | ~~Expose the `params` object.<br>Support header authentication with `authenticate_with_http_token`.<br>Router updates:<br>&emsp;• add the `resources` route helper;<br>&emsp;• add the `namespace` route helper;~~
:white_check_mark:  | ~~Add request logging.~~
:white_check_mark: | ~~Automatic code reloading in development with Zeitwerk.~~
:white_check_mark: | ~~Support conditional get with `etag` and `last_modified`.~~
:white_check_mark: | ~~Expose the `cookies` and `session` objects.~~
:white_check_mark: | ~~Implement Iodine-based equivalent of Action Cable.~~
⏳ | Expose the `send_data` and `send_file` methods.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rage-rb/rage. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

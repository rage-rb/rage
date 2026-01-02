<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.2%2B-%23f40000)

Rage is a high-performance Ruby web framework that combines the developer experience of Rails with the scalability of fiber-based concurrency. Designed for API-first applications, it allows you to handle massive traffic loads using standard synchronous Ruby code - no complex async/await syntax required.

If you love Rails but need better performance for I/O-heavy workloads, Rage provides the perfect balance: familiar conventions, low overhead, and a commitment to stability.

## Why Rage?

Building high-performance APIs in Ruby shouldn't mean abandoning the conventions you know. Rage gives you Rails-like controllers, routing, and patterns, but runs on **fiber-based concurrency** that makes your application naturally non-blocking. When your code waits on database queries, HTTP calls, or other I/O, Rage automatically handles thousands of other requests instead of sitting idle.

Rage was built to solve the performance and stability gaps that often drive teams to migrate away from Ruby, providing a modern engine that keeps the ecosystem competitive.

**Key capabilities:**

- **Rails compatibility** - Familiar controller API, routing DSL, and conventions. Migrate gradually or start fresh.
- **True concurrency** - Fiber-based architecture handles I/O without threads, locks, or async/await syntax. Your code looks synchronous but runs concurrently.
- **Zero-dependency WebSockets** - Action Cable-compatible real-time features that work out-of-the-box without Redis, even in multi-process mode.
- **Auto-generated OpenAPI** - Documentation generated from your controllers using simple comment tags.
- **In-process Background jobs** - A durable, persistent queue that runs inside your app process. No Redis or separate worker processes required.
- **Stable and focused** - Our goal is that the task "Upgrade Rage" never appears in your ticketing system. We focus strictly on APIs, maintain long-term deprecation cycles, and ensure that most updates are as simple as a `bundle update`.

Rage is API-only by design. Modern applications benefit from clear separation between backend and frontend, and Rage focuses exclusively on doing APIs well.

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

## How It Works

Rage runs each request in a separate fiber. When your code performs I/O operations - HTTP requests, database queries, file reads - the fiber automatically pauses, and Rage processes other requests. When the I/O completes, the fiber resumes exactly where it left off.

This happens transparently. You write normal Ruby code, and Rage handles the concurrency.

### Example

Here's a controller that fetches data from an external API:

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

This looks like a standard Rails controller, and it is - except during `Net::HTTP.get`, Rage automatically pauses this fiber and processes other requests. When the HTTP call completes, Rage resumes exactly where it left off. This happens automatically for HTTP requests, PostgreSQL, MySQL, and other I/O operations.

The routes are equally familiar:

```ruby
Rage.routes.draw do
  get "page", to: "pages#show"
end
```

### Parallel Execution

Need to make multiple I/O calls? Use `Fiber.await` to run them concurrently:

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

Instead of waiting for each request sequentially, Rage executes them concurrently and waits for all to complete.

## Two Ways to Use Rage

**Standalone**: Create new services with `rage new`. You get a clean project structure, CLI tools, and everything needed to build high-performance APIs from scratch.

**Rails Integration**: Add Rage to existing Rails applications for gradual migration. Use Rage for new endpoints or high-traffic routes while keeping the rest of your Rails app unchanged. See the [Rails Integration guide](https://rage-rb.dev/docs/rails) for details.

## Documentation

- [Getting Started](https://rage-rb.dev/docs/intro/) - Core concepts and setup
- [Controllers](https://rage-rb.dev/docs/controllers/) - Request handling and callbacks
- [Routing](https://rage-rb.dev/docs/routing/) - RESTful routes and namespaces
- [WebSockets](https://rage-rb.dev/docs/websockets/) - Real-time communication
- [OpenAPI](https://rage-rb.dev/docs/openapi/) - Auto-generated documentation
- [Background Jobs](https://rage-rb.dev/docs/deferred/) - In-process queue system
- [API Reference](https://rage-rb.dev/api/) - Detailed API documentation

For contributors, check the [architecture doc](https://github.com/rage-rb/rage/blob/master/ARCHITECTURE.md) to understand how Rage's components work together.

## Performance

Rage's fiber-based architecture delivers high throughput with minimal overhead. By stripping away the "framework tax", Rage gives your team more leeway to write slow-but-maintainable Ruby code without compromising the end-user experience.

#### Simple JSON responses

```ruby
class BenchmarksController < ApplicationController
  def index
    render json: { hello: "world" }
  end
end
```

![Requests per second](https://github.com/user-attachments/assets/7bb783f8-5d1b-4e7d-b14d-dafe370d1acc)


#### I/O-bound operations

```ruby
class BenchmarksController < ApplicationController
  def index
    Net::HTTP.get(URI("<endpoint-that-responds-in-one-second>"))
    head :ok
  end
end
```

![Time to complete 100 requests](https://github.com/user-attachments/assets/5155a65f-2f11-4303-b5e4-a74d3d123c16)

#### Database Queries

```ruby
class BenchmarksController < ApplicationController
  def show
    render json: World.find(rand(1..10_000))
  end
end
```

![Requests per second-2](https://github.com/user-attachments/assets/06f64a08-316f-4b24-ba2d-39ac395366aa)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rage-rb/rage. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/master/CODE_OF_CONDUCT.md).

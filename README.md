<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.3%2B-%23f40000)

**Rage** is an API-first Ruby web framework that combines the developer experience of Rails with fiber-based concurrency. You write standard synchronous Ruby code - Rage handles the concurrency, running APIs, background jobs, and WebSockets in a single process with fewer moving parts.

Rage uses Rails compatibility as a foundation and provides backend primitives optimized for a single-runtime model: background jobs that run in-process, scalable WebSockets and SSE streams, object-oriented domain events, and automatic API documentation.

## Why Rage

Modern backends are more than request/response cycles. They require:

* Asynchronous execution
* Background jobs
* Real-time communication
* Observability and telemetry
* Clear domain boundaries

In the Ruby ecosystem, these concerns typically mean more infrastructure: Redis, Sidekiq, separate worker processes, custom logging solutions, and multiple deployment units.

Rage takes a different approach: **collapse backend concerns into a single runtime** by embracing Ruby's fiber-based concurrency model. This reduces operational complexity while keeping familiar Ruby ergonomics.

## Key Capabilities

- **Rails Compatibility** - Familiar controller API, routing DSL, and conventions. Migrate gradually or start fresh.
- **True Concurrency** - Fiber-based architecture handles I/O without threads, locks, or async/await syntax. Your code looks synchronous but runs concurrently.
- **Zero-dependency WebSockets** - Action Cable-compatible real-time features that work out-of-the-box, with built-in IPC for multi-process deployments.
- **Server-Sent Events** - Native SSE streaming with no external dependencies. Built for live feeds, progress updates, and LLM response streaming.
- **Auto-generated OpenAPI** - Documentation generated from your controllers using simple comment tags.
- **In-process Background Jobs** - A durable, persistent queue that runs inside your app process. No external dependencies or separate worker processes required.
- **Built-in Observability** - Track and measure application behavior with `Rage::Telemetry`. Integrate with external monitoring platforms or build custom observability solutions.

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
$ bundle install
```

(Optional 🤖) Install agent skills:

```
$ rage skills install
```

Start up the server and visit http://localhost:3000.

```
$ rage s
```

Start coding!

## How It Works

Rage runs each request in a separate fiber. When your code performs I/O operations - HTTP requests, database queries, file reads - the fiber automatically pauses, and Rage processes other requests. When the I/O completes, the fiber resumes exactly where it left off.

This happens automatically. You write standard Ruby code, and Rage handles the concurrency.

### Unified Runtime in Action

Here's what single runtime looks like in practice:

```ruby
class OrdersController < RageController::API
  # Create an order record.
  # @request { amount: Float, product_id: Integer }
  # @response 201 Order
  def create
    order = Order.create!(order_params)

    # Schedule background job - runs in-process, no Redis needed
    SendOrderConfirmation.enqueue(order.id)

    # Broadcast to WebSocket subscribers - built in, no external services needed
    Rage::Cable.broadcast("orders", { status: "created", order_id: order.id })

    render json: order, status: :created
  end
end

# Background job - runs in the same process, persisted to disk
class SendOrderConfirmation
  include Rage::Deferred::Task

  def perform(order_id)
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver
  end
end
```

This all runs in a single process. No external queues, no separate worker dynos, no additional infrastructure.

## Two Ways to Use Rage

**Standalone**: Create new services with `rage new`. You get a clean project structure, CLI tools, and everything needed to build production-ready APIs from scratch.

**Rails Integration**: Add Rage to existing Rails applications for gradual migration. Use Rage for new endpoints or high-traffic routes while keeping the rest of your Rails app unchanged. See the [Rails Integration Guide](https://rage-rb.dev/docs/rails) for details.

## Coming from Rails?

Rage keeps the parts of Rails that work - controllers, routing, Active Record compatibility, and conventions - but rethinks how backend systems are run.

Instead of adding separate job queues, Redis, and multiple deployment units as your app grows, Rage uses Ruby's fiber-based concurrency to run APIs, background jobs, WebSockets, and domain events **in the same process**.

You write familiar synchronous Ruby code. Rage handles the concurrency.

**What changes:**

- One deployment unit instead of API servers + worker processes
- No external dependencies for jobs or broadcasts
- Domain events as objects, not string-based notifications
- OpenAPI specs generated automatically from your code

**What stays the same:**

- Controller conventions and routing DSL
- Active Record integration
- Incremental adoption for existing Rails apps

Think of Rage as Rails ergonomics with a runtime designed for modern API systems, where operational simplicity is a first-class concern.

## Stability

Rage prioritizes stable public APIs, long deprecation cycles, and minimal external dependencies. Our aspiration: the task "Upgrade Rage" never appears in your ticketing system. Most updates should be as simple as `bundle update`.

## Learn More

- Documentation: [https://rage-rb.dev](https://rage-rb.dev/docs/intro)
- API Reference: [https://rage-rb.dev/api](https://rage-rb.dev/api)
- Architecture: [ARCHITECTURE.md](https://github.com/rage-rb/rage/blob/main/ARCHITECTURE.md)
- Contributing: [CONTRIBUTING.md](https://github.com/rage-rb/rage/blob/main/CONTRIBUTING.md)

Contributions and thoughtful feedback are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/main/CODE_OF_CONDUCT.md).

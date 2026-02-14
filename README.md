<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.2%2B-%23f40000)

**Rage** is an API-first Ruby framework designed to make the Ruby ecosystem competitive for modern backends. It focuses on **capability and operational simplicity**, letting teams build production-grade systems in a single, coherent runtime.

Rage uses Rails compatibility as a foundation and provides backend primitives optimized for a single-runtime model: background jobs that run in-process, WebSockets without external dependencies, object-oriented domain events, and automatic API documentation.

## Why Rage

Modern backends are more than request/response cycles. They require:

* Asynchronous execution
* Background jobs
* Real-time communication
* Observability and telemetry
* Clear domain boundaries

In the Ruby ecosystem, these concerns typically mean more infrastructure: Redis, Sidekiq, separate worker processes, custom logging solutions, and multiple deployment units.

Rage takes a different approach: **collapse backend concerns into a single runtime** by embracing Ruby's fiber-based concurrency model. This reduces operational complexity while keeping familiar Ruby ergonomics.

### Unified Runtime in Action

Here's what single runtime looks like in practice:

```ruby
class OrdersController < RageController::API
  def create
    order = Order.create!(order_params)

    # Schedule background job - runs in-process, no Redis needed
    SendOrderConfirmation.enqueue(order.id)

    # Publish domain event - subscribers execute immediately or async
    Rage::Events.publish(OrderPlaced.new(order: order))

    # Broadcast to WebSocket subscribers - no Action Cable/Redis needed
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

# Domain event - typed, object-oriented
OrderPlaced = Data.define(:order)

# Event subscriber
class UpdateInventory
  include Rage::Events::Subscriber
  subscribe_to OrderPlaced

  def call(event)
    Inventory.decrement(event.order.items.length)
  end
end
```

This all runs in a single process. No external queues, no separate worker dynos, no Redis for pub/sub.

## Coming from Rails?

Rage keeps the parts of Rails that work - controllers, routing, Active Record compatibility, and conventions - but rethinks how backend systems are run.

Instead of adding separate job queues, Redis, and multiple deployment units as your app grows, Rage uses Ruby's fiber-based concurrency to run APIs, background jobs, WebSockets, and domain events **in the same process**.

You write familiar synchronous Ruby code. Rage handles the concurrency.

**What changes:**

- One deployment unit instead of API servers + worker processes
- No Redis required for jobs or broadcasts
- Domain events as objects, not string-based notifications
- OpenAPI specs generated automatically from your code

**What stays the same:**

- Controller conventions and routing DSL
- Active Record integration
- Incremental adoption for existing Rails apps

Think of Rage as Rails ergonomics with a runtime designed for modern API systems, where operational simplicity is a first-class concern.

## Core Ideas

### 1. Unified Backend Runtime

Rage runs HTTP APIs, background jobs, and WebSockets in the same process by default:

- No separate worker processes
- No Redis required for jobs or broadcasts
- One deployment unit for most applications

This simplifies both local development and production setup.

For high-scale scenarios, Rage supports multi-process deployments and allows Rage processes to communicate directly when needed.

### 2. API-First, Rails-Compatible

Rage provides a familiar Rails-like programming model with API-focused improvements:

- Controllers and routing that feel like Rails
- Active Record compatibility
- Incremental adoption for existing Rails applications
- OpenAPI specs auto-generated from your code

Rails compatibility is the foundation. Rage builds new primitives on top where Rails stops short.

### 3. Built-in Asynchronous Execution

Rage ships with **fiber-based, in-process background jobs**:

- Zero setup - no Redis, no configuration
- Jobs persist across restarts
- Scheduled and executed within the same runtime using fibers for concurrency

For teams that need distributed job processing, Rage works with existing solutions. But most applications can start simple and stay simple.

### 4. Structured Domain Events

Rage includes a built‑in event bus designed for **object‑oriented domain events**:

* Events are classes with explicit attributes, not hashes or strings
* Subscribers listen to event classes or mixins
* Type-safe and refactorable

This encourages clear domain modeling and avoids the brittleness of string-based notification systems.

### 5. Observability by Design

Observability is not an afterthought:

- Structured logging by default
- Dedicated observability interface for HTTP, background, and real-time features
- OpenAPI specifications generated automatically from the running application

API contracts stay in sync with code by default - no separate documentation pipelines.

### 6. Performance That Enables Simplicity

Rage's fiber-based concurrency delivers strong performance for I/O-heavy workloads, but performance is a means to an end: operational simplicity.

By handling concurrency efficiently, Rage lets you:

- Run fewer servers
- Deploy fewer services
- Skip infrastructure that only exists to work around framework limitations

The goal is to let teams write maintainable Ruby code without the "framework tax" forcing premature optimization or infrastructure sprawl.

## Philosophy

Rage is intentionally conservative about change.

The framework prioritizes:

- **Stable public APIs**
- **Long deprecation cycles**
- **Minimal external dependencies**

The goal is to let teams build systems that **age well** - without constant rewrites or growing infrastructure complexity.

Our aspiration: the task "Upgrade Rage" never appears in your ticketing system. Most updates should be as simple as `bundle update`.

## What Rage Is (and Isn't)

**Rage is:**

- Focused on backend APIs
- Opinionated about operational simplicity
- Designed for long-term stability
- Rails-compatible but architecturally independent

**Rage is not:**

- A full-stack framework - no view layer, no asset pipeline
- A Rails clone - compatibility is a bridge, not the destination
- Trying to do everything - deliberate scope boundaries

## Who Rage Is For

Rage is a good fit if you:

- Build API-only backends in Ruby
- Care about operational simplicity over maximum flexibility
- Want fewer moving parts in production
- Prefer explicit, object-oriented design
- Value long-term stability over cutting-edge features

## Learn More

- Documentation: [https://rage-rb.dev](https://rage-rb.dev/docs/intro)
- API Reference: [https://rage-rb.dev/api](https://rage-rb.dev/api)
- Architecture: [ARCHITECTURE.md](https://github.com/rage-rb/rage/blob/main/ARCHITECTURE.md)

Contributions and thoughtful feedback are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rage project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rage-rb/rage/blob/main/CODE_OF_CONDUCT.md).

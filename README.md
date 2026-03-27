<p align="center"><img height="200" src="https://github.com/rage-rb/rage/assets/2270393/9d06e0a4-5c20-49c7-b51d-e16ce8f1e1b7" /></p>

# Rage

[![Gem Version](https://badge.fury.io/rb/rage-rb.svg)](https://badge.fury.io/rb/rage-rb)
![Tests](https://github.com/rage-rb/rage/actions/workflows/main.yml/badge.svg)
![Ruby Requirement](https://img.shields.io/badge/Ruby-3.2%2B-%23f40000)

**Rage** is an API-first Ruby framework with a modern, fiber-based runtime that enables transparent, non-blocking concurrency while preserving familiar developer ergonomics. It focuses on **capability and operational simplicity**, letting teams build production-grade systems in a single, coherent runtime.

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

## Getting Started

Install the gem:
```bash
gem install rage-rb
```

Create a new Rage application:
```bash
rage new my_api
cd my_api
rage server
```

## Coming from Rails?

Rage keeps the parts of Rails that work - controllers, routing, Active Record compatibility, and conventions - but rethinks how backend systems are run.

Instead of adding separate job queues, Redi
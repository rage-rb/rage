# Contributing to Rage

This guide is designed to help contributors understand the project's internals, design principles, and conventions. Whether you're fixing a bug, adding a feature, or participating in GSoC, this document will help you get started.

## Table of Contents

- [Design Principles](#design-principles)
- [Documentation Standards](#documentation-standards)
- [Dynamic Code Generation](#dynamic-code-generation)
- [Iodine Integration](#iodine-integration)
- [The Fiber Runtime](#the-fiber-runtime)
- [A Note on AI Usage](#a-note-on-ai-usage)

## Design Principles

### Performance Over Readability

Rage is a framework, not application code. While readability matters, performance takes priority when the two conflict. Framework code runs on every request, so micro-optimizations compound into significant gains.

This doesn't mean writing deliberately obscure code. It means accepting that some patterns which would be discouraged in application code are acceptable here when they improve performance.

### Lean Happy Path

The happy path should execute as little code as possible. We achieve this through:

1. **Boot-time computation**: Move work to server startup whenever possible. Pre-compile routes, resolve callback chains, and build method definitions during initialization rather than on each request.

2. **Feature isolation**: New features should not impact performance for users who don't use them. If a feature requires runtime checks, consider whether those checks can be eliminated through code generation or configuration.

### Duplication Over Premature Abstraction

Duplication is cheaper than unnecessary abstraction.

Abstractions should emerge from observed patterns, not anticipated ones. When you see similar code in two places, resist the urge to immediately extract a helper. Introducing new abstraction layers or deduplicating code should only happen after the duplication has naturally occurred and proven to be a burden.

A wrong abstraction is worse than duplicated code because:
- It's harder to understand (you must trace through multiple layers)
- It's harder to modify (changes affect all call sites)
- It's harder to remove (it becomes load-bearing)

When you do introduce an abstraction, make sure it pulls its weight.

## Documentation Standards

### YARD Documentation

All user-facing methods must be documented using [YARD](https://yardoc.org/). Documentation comments use Markdown formatting.

```ruby
# Publish an event to all registered subscribers.
#
# @param event [Object] the event instance to publish
# @param context [Hash] optional context to pass to subscribers
# @return [void]
#
# @example Publishing an event
#   Rage::Events.publish(OrderCreated.new(order: order))
#
# @example Publishing with context
#   Rage::Events.publish(OrderCreated.new(order: order), context: { user_id: current_user.id })
#
def publish(event, context: nil)
  # ...
end
```

### The `@private` Tag

Some methods cannot be marked `private` using Ruby's `private` keyword (e.g., they need to be called from other classes within the framework), but they are not part of the public API. These methods should be marked with the `@private` YARD tag:

```ruby
# @private
# Used internally by the router to register controller actions.
def __register_action(action)
  # ...
end
```

The `@private` tag signals to contributors:
- This method is not part of the user-facing API
- It can be modified or removed without deprecation
- It can be used freely within the framework codebase

## Dynamic Code Generation

Rage relies heavily on dynamic code generation for both performance and flexibility. Understanding this pattern is essential for contributing to the framework.

### Why Dynamic Code Generation?

1. **Performance**: Generated code avoids runtime conditionals. Instead of checking "does this controller have before actions?" on every request, we generate a method that either includes the before action calls or doesn't.

2. **Flexibility**: Generated code can adapt to user-defined signatures, allowing optional parameters without forcing users to accept arguments they don't need.

### Examples in the Codebase

#### Controller Action Registration

`RageController::API.__register_action` (in `lib/rage/controller/api.rb`) generates a method for each controller action at boot time:

```ruby
class_eval <<~RUBY, __FILE__, __LINE__ + 1
  def __run_#{action}
    #{before_actions_chunk}
    #{action} unless @__before_callback_rendered
    #{after_actions_chunk}
    [@__status, @__headers, @__body]
    #{rescue_handlers_chunk}
  end
RUBY
```

This generates a single method that includes only the callbacks and exception handlers relevant to that specific action. No runtime resolution required.

#### Logger Rebuilding

`Rage::Logger#rebuild!` (in `lib/rage/logger/logger.rb`) generates logging methods based on the configured log level:

```ruby
if level_val < @level
  # Log level is filtered out - generate a no-op method
  def info(msg = nil, context = nil)
    false
  end
else
  # Generate a method that actually logs
  def info(msg = nil, context = nil)
    # ... logging implementation
  end
end
```

When logging at a level is disabled, the method becomes a no-op with zero overhead.

#### Telemetry Tracer

`Rage::Telemetry::Tracer#setup` (in `lib/rage/telemetry/tracer.rb`) generates tracing methods that call only the handlers registered for each span. If no handlers are registered, it generates a pass-through method.

### Dynamic Keyword Arguments

One pattern Rage uses extensively is dynamic keyword arguments. This allows users to define methods that accept only the parameters they care about, without requiring `**` to absorb extras.

For example, an event subscriber can be defined either way:

```ruby
# Subscriber that only cares about the event
def call(event)
end

# Subscriber that also needs context
def call(event, context:)
end
```

Both work regardless of whether the event was published with context. The framework inspects the method signature and generates a call that passes only the expected arguments.

The `Rage::Internal.build_arguments` method (in `lib/rage/internal.rb`) implements this pattern:

```ruby
def build_arguments(method, arguments)
  expected_parameters = method.parameters

  arguments.filter_map { |arg_name, arg_value|
    if expected_parameters.any? { |param_type, param_name| param_name == arg_name || param_type == :keyrest }
      "#{arg_name}: #{arg_value}"
    end
  }.join(", ")
end
```

This inspects the target method's parameters and generates a string containing only the arguments that method expects. The generated string is then embedded into dynamically defined code.

This pattern appears in:
- Event subscribers (accepting event with optional context)
- Telemetry handlers (accepting various span attributes)
- External loggers (accepting severity, message, context, etc.)

## Iodine Integration

Rage consists of two components: the framework (this repository) and its server, [Iodine](https://github.com/rage-rb/iodine). Iodine is not an external dependency; it's part of the Rage runtime, and its methods can be used freely within the codebase.

### Useful Iodine Methods

**`Iodine.run_after(milliseconds) { ... }`**: Schedule a block to run after a delay.

```ruby
Iodine.run_after(5000) do
  cleanup_expired_sessions
end
```

**`Iodine.run_every(milliseconds) { ... }`**: Schedule a block to run at regular intervals.

```ruby
Iodine.run_every(60_000) do
  report_metrics
end
```

**`Iodine.publish(channel, message, engine)`**: Send a message to subscribers. This is used for inter-fiber and inter-process communication.

```ruby
# Notify within the current process
Iodine.publish("my_channel", "message", Iodine::PubSub::PROCESS)

# Notify across all processes in the cluster
Iodine.publish("my_channel", "message", Iodine::PubSub::CLUSTER)
```

**`Iodine.on_state(state) { ... }`**: Register callbacks for server lifecycle events.

```ruby
Iodine.on_state(:on_start) do
  # Runs when the worker process starts
end
```

## The Fiber Runtime

### Rage::FiberWrapper

`Rage::FiberWrapper` (in `lib/rage/middleware/fiber_wrapper.rb`) is the glue between the framework and the server. It sits at the top of the middleware stack and:

1. Wraps every request in a Fiber
2. Implements the defer protocol for pausing/resuming async requests

When a request encounters blocking I/O (database query, HTTP request, etc.), the fiber yields. `FiberWrapper` detects this (`fiber.alive?`) and returns a special `:__http_defer__` signal to Iodine, which pauses the connection.

When the I/O completes, the fiber resumes and publishes a message to notify Iodine that the response is ready. This is the mechanism that enables transparent, non-blocking concurrency.

## A Note on AI Usage

Contributors are free to use AI tools however they see fit.

One thing to keep in mind: when delegating development to AI, the friction this removes is the very friction that enables developers to understand the system, learn, and grow as professionals.

There's value in the struggle of tracing through code, understanding why something was designed a certain way, and building mental models of complex systems. Use AI to assist and accelerate, but ensure you are still engaging deeply with the architecture and the "why" behind the code you are committing.

---

Questions? Open an issue or reach out to the maintainers.

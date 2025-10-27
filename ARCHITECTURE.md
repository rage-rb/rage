### Table of Contents

[API Workflow](#api-workflow)<br>
[Executing Controller Actions](#executing-controller-actions)<br>
[Cable Workflow](#cable-workflow)<br>
[OpenAPI Workflow](#openapi-workflow)<br>
[Design Principles](#design-principles)<br>

### API Workflow

The following diagram describes some of Rage's internal components and the way they interact with each other:

![overview](https://github.com/rage-rb/rage/assets/2270393/0d45bbe3-622c-4b17-b8d8-552c567fecb3)

### Executing Controller Actions

To maximize runtime performance, Rage pre-compiles controller actions when the application boots. For each action, it resolves the full chain of callbacks and exception handlers, building a single, optimized procedure.

When a request comes in, Rage executes this pre-compiled procedure directly, avoiding the overhead of resolving callbacks and exception handlers on every request. All of this happens at boot time to ensure the request-response cycle is as fast as possible.

### Cable Workflow

`Rage::Cable` provides a component for handling real-time communication over WebSockets. The workflow involves authenticating connections and subscribing them to channels for bidirectional messaging.

The following diagram describes the components of a `Rage::Cable` application:

![cable](https://github.com/user-attachments/assets/86db2091-f93a-44f8-9512-c4701770d09e)

### OpenAPI Workflow

`Rage::OpenAPI` generates OpenAPI 3.0 specifications by parsing comments in controller files. This process happens at boot time, building the specification and storing it in memory to be served for API documentation.

The following diagram describes the flow of `Rage::OpenAPI`:

<img width="800" src="https://github.com/user-attachments/assets/b4a87b1e-9a0f-4432-a3e9-0106ff546f3f" />

### Design Principles

* **Lean Happy Path:** We try to execute as many operations as possible during server initialization to minimize workload during request processing. Additionally, new features should be designed to avoid impacting the framework performance for users who do not utilize those features.

* **Performance Over Code Style:** We recognize that framework and application code have different requirements. While testability and readability are crucial for application code, framework code prioritizes performance and careful abstraction. This allows for future modifications while maintaining backward compatibility, though readability remains important.

* **Rails Compatibility:** A key objective is to provide a familiar experience for Rails developers, with the Controller and Cable APIs being largely compatible. However, Rage is not a reimplementation of Rails. Instead, it provides a familiar foundation and builds upon it with its own unique features.

* **Idiomatic Ruby:** We prioritize idiomatic Ruby, avoiding unnecessary abstractions. User-level code is expected to embrace standard Ruby syntax, approaches, and patterns, as this is preferable to a framework-level abstraction that accomplishes the same task.

* **Single-Threaded Fiber-Based Approach:** Each request is processed in a separate, isolated execution context (Fiber), pausing whenever it encounters blocking I/O. The single-threaded approach eliminates thread synchronization overhead, leading to enhanced performance and simplified code.

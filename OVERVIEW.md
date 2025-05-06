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

When `Rage::Router::DSL` parses the `config/routes.rb` file and calls the `Rage::Router::Backend` class, it registers actions and stores handler procs.

Consider we have the following controller:

```ruby
class UsersController < RageController::API
  before_action :find_user
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def show
    render json: @user
  end

  private

  def find_user
    @user = User.find(params[:id])
  end

  def render_not_found(_)
    render status: :not_found
  end
end
```

Before processing requests to `UsersController#show`, Rage has to [register](https://github.com/rage-rb/rage/blob/master/lib/rage/controller/api.rb#L11) the show action. Registering means defining a new method that will look like this:

```ruby
class UsersController
  def __run_show
    find_user
    show
  rescue ActiveRecord::RecordNotFound => e
    render_not_found(e)
  end
end
```

After that, Rage will create and store a handler proc that will look exactly like this:

```ruby
->(env, params) { UsersController.new(env, params).__run_show }
```

All of this happens at boot time. Once the request comes in at runtime, Rage will only need to retrieve the handler proc defined earlier and call it.

### Cable Workflow

The following diagram describes the components of a `Rage::Cable` application:

![cable](https://github.com/user-attachments/assets/86db2091-f93a-44f8-9512-c4701770d09e)

### OpenAPI Workflow

The following diagram describes the flow of `Rage::OpenAPI`:

<img width="800" src="https://github.com/user-attachments/assets/b4a87b1e-9a0f-4432-a3e9-0106ff546f3f" />

### Design Principles

* **Lean Happy Path:** we try to execute as many operations as possible during server initialization to minimize workload during request processing. Additionally, new features should be designed to avoid impacting the framework performance for users who do not utilize those features.

* **Performance Over Code Style:** we recognize the distinct requirements of framework and client code. Testability, readability, and maintainability are crucial for client code used in application development. Conversely, library code addresses different tasks and should be designed with different objectives. In library code, performance and abstraction to enable future modifications while maintaining backward compatibility take precedence over typical client code concerns, though testability and readability remain important.

* **Rails Compatibility:** Rails compatibility is a key objective to ensure a seamless transition for developers. While it may not be feasible to replicate every method implemented in Rails, the framework should function in a familiar and expected manner.

* **Single-Threaded Fiber-Based Approach:** each request is processed in a separate, isolated execution context (Fiber), pausing whenever it encounters blocking I/O. This single-threaded approach eliminates thread synchronization overhead, leading to enhanced performance and simplified code.

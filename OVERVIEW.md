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

![cable](https://github.com/user-attachments/assets/a903ad02-9002-441f-bcd9-d6274ef8a5bd)

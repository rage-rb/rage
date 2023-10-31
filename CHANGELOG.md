## [Unreleased]

## [0.4.0] - 2023-10-31

### Added

- Expose the `params` object.
- Support header authentication with `authenticate_with_http_token`.
- Add the `resources` and `namespace` route helpers.
- Add the `mount` and `match` route helpers.
- Allow to access request headers.
- Support custom ports when starting the app with `rage s`.

## [0.3.0] - 2023-10-08

### Added

- CLI `routes` task.
- CLI `console` task.
- `:if` and `:unless` options in `before_action`.
- Allow to set response headers.
- Block version of `before_action`.

## [0.2.0] - 2023-09-27

### Added

- Gem configuration by env.
- Add `skip_before_action`.
- Add `rescue_from`.
- Add `Fiber.await`.
- Support the `defaults` route option.

### Fixed

- Ignore trailing slashes in the URLs.
- Support constraints in routes with optional params.
- Make the `root` routes helper work correctly with scopes.
- Convert objects to string when rendering text.

## [0.1.0] - 2023-09-15

- Initial release
  - Add console utility to generate new apps and start up the server.
  - Implement base API controller:
    - support `before_action` with the `only` and `except` options;
    - support `render` with the `json`, `plain` and `status` options;
    - support the `head` method;
  - Implement router:
    - support the `root`, `get`, `post`, `patch`, `put`, `delete` methods;
    - support the `scope` method with the `path` and `module` options;
    - support `host` constraint;


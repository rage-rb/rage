## [Unreleased]

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


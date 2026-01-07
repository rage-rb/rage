## [Unreleased]

## [1.19.2] - 2026-01-06

### Changed

- Compatibility with Rack 3 (#193).

## [1.19.1] - 2025-12-26

### Changed

- Use app-specific cookie keys for sessions (#189).

## [1.19.0] - 2025-12-03

### Added

- Add ability to specify external loggers (#178).
- Pass all of log data to deferred tasks (#173).
- Add the `Request#route_uri_pattern` method (#175).
- Support global log tags and context (#171, #177).

### Fixed

- Fix reloading in dev with user-level fibers (#170).

## [1.18.0] - 2025-10-29

### Added

- Add `Rage::Events` (#167).

### Fixed

- Fix sequential `Fiber.await` calls (#168).

## [1.17.1] - 2025-08-21

### Fixed

- Apply backpressure to every `enqueue` call (#166).

## [1.17.0] - 2025-08-20

### Added

- Add `Rage::Deferred` (#164).
- Add a controller generator by [@alex-rogachev](https://github.com/alex-rogachev) (#160).
- Update `stale?` to set cache headers by [@serhii-sadovskyi](https://github.com/serhii-sadovskyi) (#159).

### Fixed

- Sub-millisecond sleep results in hang (#161).

## [1.16.0] - 2025-05-20

### Added

- [Cable] Add the `RawJSON` protocol (#150).
- Add the `after_initialize` hook by [@serhii-sadovskyi](https://github.com/serhii-sadovskyi) (#149).

### Fixed

- Correctly parse plaintext responses in RSpec (#151).
- [OpenAPI] Correctly handle `root_key!` (#148).
- [OpenAPI] Correctly handle the `key` option in associations (#147).

## [1.15.1] - 2025-04-17

### Fixed

- [Cable] Create a subscription only when the reactor is started (#146).

## [1.15.0] - 2025-04-02

### Added

- Enhance the `Rage::Request` class by [@aaoafk](https://github.com/aaoafk) (#123).
- [OpenAPI] Support the `@param` tag (#134).

### Fixed

- Fix using `Fiber.schedule` in console by [@lkibbalam](https://github.com/lkibbalam) (#143).
- Correctly handle regexp origins in `Rage::Cors` (#138).
- [OpenAPI] Correctly handle trailing slash (#141).
- [OpenAPI] Correctly handle empty shared components (#139).
- [OpenAPI] Explicitly load Prism (#136).
- [OpenAPI] Correctly verify available before actions (#144).
- [OpenAPI] Correctly handle global comments (#140).

## [1.14.0] - 2025-03-10

### Added

- Detect file updates in development (#132).

### Fixed

- Update app template to include all app rake tasks by [pjb3](https://github.com/pjb3) (#130).

## [1.13.0] - 2025-02-12

### Added

- [CLI] Support the PORT ENV variable by [@TheBlackArroVV](https://github.com/TheBlackArroVV) (#124).
- Add the `RequestId` middleware (#127).

### Fixed

- Correctly process persistent HTTP connections (#128).
- [OpenAPI] Ignore empty comments (#126).
- [Cable] Improve the time to connect (#129).

## [1.12.0] - 2025-01-21

### Added

- Add Redis adapter (#114).
- Add global response tags (#110).
- Implement around_action callbacks (#107).

### Fixed

- Support date types in Alba serializers (#112).

## [1.11.0] - 2024-12-18

### Added

- `Rage::OpenAPI` (#109).

### Fixed

- Correctly handle ActiveRecord connections in the environments with `legacy_connection_handling == false` (#108).

## [1.10.1] - 2024-09-17

### Fixed

- Patch AR pool even if `Rake` is defined (#105).

## [1.10.0] - 2024-09-16

### Changed

- Enable Rage Connection Pool by default (#103).
- Allow to preconfigure the app for selected database (#104).

### Added

- Add `version` and `middleware` CLI commands (#99).

## [1.9.0] - 2024-08-24

### Added

- Static file server (#100).
- Rails 7.2 compatibility (#101).

### Fixed

- Correctly set Rails env (#102).

## [1.8.0] - 2024-08-06

### Added

- Support WebSockets (#88).

## [1.7.0] - 2024-07-30

### Added

- Support `wrap_parameters` by [@alex-rogachev](https://github.com/alex-rogachev) (#89).
- Unknown environment error handling by [@cuneyter](https://github.com/cuneyter) (#95).
- Allow `rescue_from` handlers to not accept arguments (#93).

## [1.6.0] - 2024-07-15

### Added

- Support legacy route helpers (#90).
- Correctly handle internal Rails routes in `Rage.multi_application` (#91).

## [1.5.1] - 2024-05-26

### Fixed

- Correctly reload code in multi apps (#87).

## [1.5.0] - 2024-05-08

### Added

- Allow to have both Rails and Rage controllers in one application (#83).
- Add `authenticate_or_request_with_http_token` (#85).
- Add the `member` and `controller` route helpers (#86).

### Changed

- Deprecate `Rage.load_middlewares` (#83).

### Fixed

- Correctly init console in Rails mode (credit to [efibootmgr](https://github.com/efibootmgr)) (#84).

## [1.4.0] - 2024-05-01

### Added

- Support cookies and sessions (#69).

### Fixed

- Improve compatibility with ActiveRecord 7.1 (#80).

## [1.3.0] - 2024-04-17

### Added

- Introduce the `ActiveRecord::ConnectionPool` patch (#78).

## [1.2.2] - 2024-04-03

### Fixed

- Correctly determine Rage env (#77).

## [1.2.1] - 2024-04-03

### Fixed

- Correctly clone Rails logger (#76).

## [1.2.0] - 2024-04-03

### Changed

- Disable Ruby buffer for logging IO (#73).
- Default to 1 worker in development (#74).
- Default to use ActionDispatch::Reloader in dev env in Rails mode (#75).

## [1.1.0] - 2024-03-25

### Changed

- Change the way controller names are logged (#72).
- Use formatters in console (#71).

### Fixed

- Fix Fiber.await behavior in RSpec (#70).

## [1.0.0] - 2024-03-13

### Added

- RSpec integration (#60).
- Add DNS cache (#65).
- Allow to disable the `FiberScheduler#io_write` hook (#63).

### Fixed

- Preload fiber ID (#62).
- Release ActiveRecord connections on yield (#66).
- Logger fixes (#64).
- Fix publish calls in cluster mode (#67).

## [0.7.0] - 2024-01-09

- Add conditional GET using `stale?` by [@tonekk](https://github.com/tonekk) (#55).
- Add Rails integration (#57).
- Add JSON log formatter (#59).

## [0.6.0] - 2023-12-22

### Added

- Implement after actions (#53).
- Zeitwerk autoloading and reloading by [@alex-rogachev](https://github.com/alex-rogachev) (#54).
- Support the `environment`, `binding`, `timeout`, and `max_clients` options when using `rage s` (#52).
- Add CORS middleware (#49).

### Fixed

- Prevent `block` and `sleep` channels from conflicting (#51).

## [0.5.2] - 2023-12-11

### Added

- Add env class (#43).

### Changed

- Schedule request Fibers in a separate middleware (#48).

## [0.5.1] - 2023-12-01

### Fixed

- Fix logging inside detached fibers (#41).
- Allow to configure the logger as `nil` (#42).

## [0.5.0] - 2023-11-25

### Added

- Add sessions for compatibility with `Sidekiq::Web` (#35).
- Add logger (#33).

### Fixed

- Fixes for `FiberScheduler#io_wait` and `FiberScheduler#io_read` (#32).
- Correctly handle exceptions in inner fibers (#34).
- Fixes for `FiberScheduler#kernel_sleep` (#36).

### Changed

- Use config namespaces (#25).
- Update `Fiber.await` signature (#36).

## [0.4.0] - 2023-10-31

### Added

- Expose the `params` object (#23).
- Support header authentication with `authenticate_with_http_token` (#21).
- Add the `resources` route helper (#20).
- Add the `namespace` route helper by [@arikarim](https://github.com/arikarim) (#17).
- Add the `mount` and `match` route helpers by [@arikarim](https://github.com/arikarim) (#18) (#14).
- Allow to access request headers by [@arikarim](https://github.com/arikarim) (#15).
- Support custom ports when starting the app with `rage s`.

## [0.3.0] - 2023-10-08

### Added

- CLI `routes` task by [@arikarim](https://github.com/arikarim) (#9).
- CLI `console` task (#12).
- `:if` and `:unless` options in `before_action` (#10).
- Allow to set response headers (#11).
- Block version of `before_action` by [@heysyam99](https://github.com/heysyam99) (#8).

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


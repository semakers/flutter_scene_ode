# flutter_scene_ode_core

The pure-Dart core of [flutter_scene_ode](https://pub.dev/packages/flutter_scene_ode):
an [ODE](https://www.ode.org/) physics backend for the `PhysicsSimulation`
contract of [`package:scene`](https://pub.dev/packages/scene).

It has no Flutter dependency, so it runs in `dart run`, in tests and in
`dart compile exe` programs, such as a headless server that evaluates
simulations. In a Flutter app, depend on `flutter_scene_ode` instead: it
re-exports this package and bundles the native binaries for Android, iOS,
macOS, Windows and the web.

## The native library

This package loads ODE at runtime and does not ship it. Point it at a
single-precision `libode` with the `ODE_LIBRARY_PATH` environment variable.
The repository's `tool/build_vendored_host.sh` builds one for the current
machine from the same sources the plugin uses.

## Example

See [example/example.dart](example/example.dart): a box falls, lands at
y = 1.25 and goes to sleep.

```bash
ODE_LIBRARY_PATH=/path/to/libode.so dart run example/example.dart
```

Units, supported features and known limits are documented in the
[main README](https://gitlab.com/amiba_proteus/flutter_scene_ode).

## License

BSD 3-Clause. See [LICENSE](LICENSE).

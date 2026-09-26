# flutter_scene_ode

A physics backend for [flutter_scene](https://pub.dev/packages/flutter_scene)
built on **ODE**, the [Open Dynamics Engine](https://www.ode.org/). It
implements the `PhysicsSimulation` contract of
[`package:scene`](https://pub.dev/packages/scene): rigid bodies, motorised
hinges, fixed joints, contacts with friction, sleeping bodies and raycasts.

ODE has been used for two decades in robotics simulators. This backend was
born inside Nairda, and the binaries shipped here are the same ones that run
there.

To our knowledge (September 2026) it is the first physics backend for
flutter_scene written outside the flutter_scene project, and the first one
based on ODE. The other backends are
[flutter_scene_rapier](https://pub.dev/packages/flutter_scene_rapier) and
[flutter_scene_box3d](https://pub.dev/packages/flutter_scene_box3d).

![The example app: boxes, spheres and cylinders simulated by ODE and drawn by flutter_scene, on the web](https://raw.githubusercontent.com/semakers/flutter_scene_ode/main/doc/example.png)

## Where it is used

- **[Nairda](https://nairda.com.mx)** is an educational robotics app. ODE
  simulates the robots children build, with servos, DC motors, wheels and
  bumpers, on Android, iOS, macOS, Windows and the web. Nairda's virtual
  robot contests also run this physics on a server, through the pure-Dart
  core and without Flutter.
- **[Proteus](https://github.com/semakers/proteus)** is an artificial-life experiment: an amoeba whose body is
  simulated by ODE. A small decision model moves its pseudopods, and a
  language model narrates its inner state as a "Cartesian theatre" that
  steers the amoeba towards homeostasis. It uses the pure-Dart core for the
  simulation and flutter_scene for its 3D viewer. Code on
  [GitHub](https://github.com/semakers/proteus), live demo at
  https://proteus.nairda-back.com.

*Documentación en español: [README.es.md](README.es.md).*

## Platforms

| Platform | How ODE gets there |
|---|---|
| Android (`arm64-v8a`) | prebuilt `libode.so`, 747 KB |
| iOS, macOS | the podspec compiles the bundled C++ sources |
| Windows (x64) | `windows/CMakeLists.txt` compiles the same sources with MSVC |
| Web | prebuilt `ode.wasm`, 122 KB |
| Linux | not bundled: `isAvailable` is false (you can load your own `libode`) |

Nothing crashes where ODE is missing. `OdeSimulation.isAvailable` and
`OdeSimulation.unavailableReason` tell you before you create anything.

## Install

```yaml
dependencies:
  flutter_scene_ode: ^0.1.0
```

For a program **without Flutter** (a server, a CLI, a headless evaluator), use
the pure-Dart core instead:
[`flutter_scene_ode_core`](core/README.md). It is the same code; this plugin
only adds the native binaries and the web module.

## Use

```dart
import 'package:flutter_scene_ode/flutter_scene_ode.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

Future<void> main() async {
  // On the web this downloads ode.wasm from the asset bundle.
  await FlutterSceneOde.ensureAvailable();
  if (!OdeSimulation.isAvailable) {
    print('No physics here: ${OdeSimulation.unavailableReason}');
    return;
  }

  final sim = OdeSimulation();

  final ground = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, -1, 0)),
    type: BodyType.fixed,
  );
  sim.createColliders(ground, BoxShape(halfExtents: Vector3(50, 1, 50)));

  final box = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, 7, 0)),
    type: BodyType.dynamic_,
    additionalMass: 7.0, // grams
  );
  sim.createColliders(box, BoxShape(halfExtents: Vector3(1.5, 1.25, 0.66)));

  for (var t = 0.0; t < 6.0; t += sim.fixedTimestep) {
    sim.step(sim.fixedTimestep);
  }
  final (position, _) = sim.readBodyPose(box);
  print('resting at y = ${position.y}'); // 1.25

  sim.dispose(); // required: the native world keeps the process alive
}
```

Two runnable examples:

- [`example/`](example/) is a Flutter app: boxes, spheres and cylinders rain
  onto a floor, through flutter_scene's `PhysicsWorld` component.
- [`core/example/example.dart`](core/example/example.dart) is the same idea
  in pure Dart, without Flutter.

## Units and tuning

The world is tuned for **small robots**: 1 unit ≈ 1 cm, masses in **grams**,
gravity −9.81 along Y. The fixed step is 1/240 s with up to 16 substeps. The
solver runs 40 QuickStep iterations with CFM 1e‑5 and ERP 0.2, and bodies go
to sleep when they come to rest.

These values were measured, not guessed. With masses in kilograms, a servo of
a few grams leaves the solver's multipliers near the float epsilon and the
assembly never stops rocking. The reasons for every constant are written in
the comments of `core/lib/src/ode/ode_simulation.dart`.

## What is supported

| Feature | Status |
|---|---|
| Body types | dynamic, kinematic, fixed |
| Shapes | box, sphere, cylinder, flat compounds of those |
| Joints | hinge with motor and limits, fixed |
| Contacts | friction (average or minimum), mechanism groups that ignore self-contact |
| Queries | `raycast`, `raycastAll`, contact map between steps |
| Sleeping | automatic, with `wakeBody` / `sleepBody` |
| Web | the same Dart code, through a small `dart:ffi` shim over WebAssembly |

## Known limits

- **Single precision only.** The library checks the ABI at startup and refuses
  a double-precision build instead of reading garbage.
- **No capsules.** ODE is compiled without libccd, so capsule↔cylinder
  collisions would pass through silently. `CapsuleShape` throws on purpose.
- **No cylinder↔cylinder contact**, for the same reason.
- No restitution, triggers, CCD, axis locks, character controller or world
  snapshots.
  `overlapSphere`, `overlapBox` and `shapeCast` return nothing yet.
- Android ships `arm64-v8a` only.
- The source comments are in Spanish. Pull requests that translate them are
  welcome.

## How the native side is built

[`NATIVE.md`](NATIVE.md) explains every step, in Spanish: the ODE 0.16.6
tarball and its SHA256, the compiler flags, why libccd is off, why the Apple
pod is a dynamic framework, and how the WebAssembly module is built with
Emscripten. The scripts are in `tool/`.

The tests run on the host in seconds, without a phone:

```bash
tool/build_vendored_host.sh               # prints the path of libode
cd core
ODE_LIBRARY_PATH=<that path> dart test    # 59 tests (and `flutter test` at the root: 64)
```

## License

BSD 3-Clause, see [LICENSE](LICENSE). ODE is used and redistributed under its
BSD-style license, see [LICENSE-ODE-BSD.txt](LICENSE-ODE-BSD.txt) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

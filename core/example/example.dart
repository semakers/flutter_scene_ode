// A box falls onto the ground, lands and goes to sleep.
//
// Run it from `core/` with a native ODE library built for this machine:
//
//   tool/build_vendored_host.sh   # prints the path of libode
//   ODE_LIBRARY_PATH=<that path> dart run example/example.dart
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

Future<void> main() async {
  // On the web this downloads the WebAssembly module; natively it is instant.
  await OdeSimulation.ensureAvailable();
  if (!OdeSimulation.isAvailable) {
    print('ODE is not available: ${OdeSimulation.unavailableReason}');
    return;
  }

  // Units: 1 unit = 1 cm, masses in grams, gravity -9.81 along Y.
  final sim = OdeSimulation();

  // The ground: a fixed box whose top face sits at y = 0.
  final ground = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, -1, 0)),
    type: BodyType.fixed,
  );
  sim.createColliders(ground, BoxShape(halfExtents: Vector3(50, 1, 50)));

  // A 7 g box dropped from y = 7.
  final box = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, 7, 0)),
    type: BodyType.dynamic_,
    additionalMass: 7.0,
  );
  sim.createColliders(
    box,
    BoxShape(halfExtents: Vector3(1.5, 1.25, 0.66)),
    material: PhysicsMaterial(friction: 0.8),
  );

  for (var t = 0.0; t < 6.0; t += sim.fixedTimestep) {
    sim.step(sim.fixedTimestep);
  }

  final (position, _) = sim.readBodyPose(box);
  print('resting at y = ${position.y.toStringAsFixed(2)}, '
      'sleeping: ${sim.isBodySleeping(box)}');

  // Without dispose() the native world keeps the process alive.
  sim.dispose();
}

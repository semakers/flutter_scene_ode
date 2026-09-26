// Sin gravedad ni suelo: ¿la orden de reposo (30/24) deja los pies PLANOS
// (up = +Y) y las piernas verticales? Si no, la pre-rotación del generador va
// al revés.
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:vector_math/vector_math.dart';

import '../ode_test_util.dart';
import 'otto_replica.dart';

void main() {
  setUpAll(exigirOde);

  test('la orden de reposo endereza los pies en el aire', () {
    final sim = OdeSimulation();
    final o = buildOtto();
    spawn(sim, o);
    for (final c in o.cajas) {
      sim.setBodyGravityScale(c.handle, 0);
    }
    print('  inicial: ${estado(sim, o)}');
    for (final b in o.bisagras) {
      b.target = radians(b.id.startsWith('cadera') ? 30 : 24);
    }
    run(sim, o, 4.0);
    print('  final:   ${estado(sim, o)}');
    for (final id in ['pie_izq', 'pie_der', 'pierna_izq', 'pierna_der']) {
      final (_, q) = sim.readBodyPose(o.byId[id]!.handle);
      final up = act(q, Vector3(0, 1, 0));
      final fwd = act(q, Vector3(0, 0, 1));
      print('  $id up=$up fwd=$fwd');
    }
    sim.dispose();
  });
}

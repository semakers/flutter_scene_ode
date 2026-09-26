// ¿Qué hace +4/−4 en los tobillos: puntillas simétricas o ESCORA?
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:vector_math/vector_math.dart';

import '../ode_test_util.dart';
import 'otto_replica.dart';

void main() {
  setUpAll(exigirOde);
  test('tiptoe', () {
    for (final (l, r) in [(24.0, 24.0), (28.0, 20.0), (20.0, 28.0), (30.0, 30.0), (18.0, 18.0)]) {
      final sim = OdeSimulation();
      addGround(sim, friction: 0.8);
      final o = buildOtto();
      spawn(sim, o);
      run(sim, o, 1.0);
      for (var k = 1; k <= 10; k++) {
        for (final b in o.bisagras) {
          b.target = radians((b.id.startsWith('cadera') ? 30 : 24) * k / 10);
        }
        run(sim, o, 0.3);
      }
      run(sim, o, 2.0);
      // sin gravedad para ver la GEOMETRÍA de la orden, no el equilibrio
      for (final c in o.cajas) sim.setBodyGravityScale(c.handle, 0);
      o.byIdBisagra('tobillo_izq').target = radians(l);
      o.byIdBisagra('tobillo_der').target = radians(r);
      run(sim, o, 3.0);
      final (pc, qc) = sim.readBodyPose(o.byId['cuerpo']!.handle);
      final upC = act(qc, Vector3(0, 1, 0));
      String pie(String id) {
        final (p, q) = sim.readBodyPose(o.byId[id]!.handle);
        final up = act(q, Vector3(0, 1, 0));
        return '$id x=${p.x.toStringAsFixed(2)} y=${p.y.toStringAsFixed(2)} up.x=${up.x.toStringAsFixed(3)}';
      }
      print('tobillos ($l, $r): cuerpo x=${pc.x.toStringAsFixed(2)} up.x=${upC.x.toStringAsFixed(3)} | ${pie('pie_izq')} | ${pie('pie_der')}');
      sim.dispose();
    }
  });
}

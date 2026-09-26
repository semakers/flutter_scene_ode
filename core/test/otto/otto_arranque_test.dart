// ¿Qué secuencia de arranque lleva al Otto de la pose guardada (todo a 0) a
// la de reposo (caderas 30, tobillos 24) con los dos pies planos?
//
// Correr en Chrome (en esta caja el libode del host no casa con el
// flutter_tester): ver `nairda-otto-bipedo`.
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:vector_math/vector_math.dart';

import '../ode_test_util.dart';
import 'otto_replica.dart';

typedef Rampa = void Function(Otto o, double t);

void rampaLineal(Otto o, double t, {required double dur, double hip = 30, double ank = 24,
    Map<String, double>? desde}) {
  final f = (t / dur).clamp(0.0, 1.0);
  for (final b in o.bisagras) {
    final home = b.id.startsWith('cadera') ? hip : ank;
    final ini = desde?[b.id] ?? 0.0;
    b.target = radians(ini + (home - ini) * f);
  }
}

void escenario(String nombre, Otto o, Rampa rampa, {double total = 8}) {
  final sim = OdeSimulation();
  addGround(sim, friction: 0.8);
  spawn(sim, o);
  run(sim, o, 1.0);
  print('== $nombre');
  print('  asentado: ${estado(sim, o)}');
  var t = 0.0;
  while (t < total) {
    rampa(o, t);
    run(sim, o, 0.5);
    t += 0.5;
    print('  t=${t.toStringAsFixed(1)} ${estado(sim, o)}');
  }
  sim.dispose();
}

void main() {
  setUpAll(exigirOde);

  test('A: los cuatro a la vez, rampa 3 s', () {
    escenario('A todos a la vez', buildOtto(), (o, t) => rampaLineal(o, t, dur: 3));
  });

  test('B: tobillos primero, caderas después', () {
    escenario('B tobillos→caderas', buildOtto(), (o, t) {
      for (final b in o.bisagras) {
        if (b.id.startsWith('tobillo')) b.target = radians(24 * (t / 3).clamp(0, 1));
        if (b.id.startsWith('cadera')) b.target = radians(30 * ((t - 3) / 3).clamp(0, 1));
      }
    });
  });

  test('C: caderas primero, tobillos después', () {
    escenario('C caderas→tobillos', buildOtto(), (o, t) {
      for (final b in o.bisagras) {
        if (b.id.startsWith('cadera')) b.target = radians(30 * (t / 3).clamp(0, 1));
        if (b.id.startsWith('tobillo')) b.target = radians(24 * ((t - 3) / 3).clamp(0, 1));
      }
    });
  });

  test('D: de una en una', () {
    const orden = ['tobillo_izq', 'tobillo_der', 'cadera_izq', 'cadera_der'];
    escenario('D una a una', buildOtto(), (o, t) {
      for (final b in o.bisagras) {
        final i = orden.indexOf(b.id);
        final home = b.id.startsWith('cadera') ? 30.0 : 24.0;
        b.target = radians(home * ((t - 1.5 * i) / 1.5).clamp(0, 1));
      }
    });
  });

  test('E: tumbado sobre el pie izquierdo, todos a la vez', () {
    escenario('E tumbado', buildOtto(tumbarSobreLosPies: true),
        (o, t) => rampaLineal(o, t, dur: 3));
  });

  test('F: salto seco (sin rampa)', () {
    escenario('F salto', buildOtto(), (o, t) => rampaLineal(o, t, dur: 0.01));
  });
}

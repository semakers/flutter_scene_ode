// Quién está TOCANDO algo: el extra que hace posible una entrada digital que
// se acciona al chocar (el sensor de límite del mecano) en vez de con el dedo.
//
// Lo que estos tests fijan, que es justo lo que puede romperse en silencio:
//  - el mapa se vacía al EMPEZAR el paso, no al terminar: quien lo consulta lo
//    hace entre pasos, y limpiarlo al final le enseñaría siempre vacío;
//  - dos cuerpos del MISMO grupo de mecanismo no se cuentan entre sí — es la
//    regla que impide que un bumper se dispare con su propio chasis;
//  - un cuerpo suelto en el aire no toca nada, y eso incluye el primer paso.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_contactos_test.dart
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

/// Caja dinámica de 1×1×1 (semiextensión 0.5) con el centro en [center].
int addBox(OdeSimulation sim, Vector3 center, {double mass = 100}) {
  final body = sim.createBody(
    target: SimplePoseTarget(translation: center),
    type: BodyType.dynamic_,
  );
  sim.createColliders(body, BoxShape(halfExtents: Vector3.all(0.5)));
  sim.setBodyAdditionalMass(body, mass);
  return body;
}

void main() {
  setUpAll(exigirOde);

  test('dos cajas que se tocan y dos que no', () {
    final sim = OdeSimulation();
    addGround(sim);
    // Solapadas 0.1 en X: hay contacto desde el primer paso.
    final a = addBox(sim, Vector3(0, 3, 0));
    final b = addBox(sim, Vector3(0.9, 3, 0));
    // Y una tercera lejos, en el aire, que no puede tocar nada todavía.
    final lejos = addBox(sim, Vector3(20, 30, 0));

    // Antes de cualquier paso NADIE toca nada: el mapa nace vacío.
    expect(sim.bodyTouching(a), isFalse, reason: 'antes del primer step');
    expect(sim.bodyTouching(lejos), isFalse);

    sim.step(sim.fixedTimestep);

    expect(sim.bodyTouching(a), isTrue);
    expect(sim.bodyTouching(b), isTrue);
    expect(sim.bodyContactDepth(a), greaterThan(0));
    expect(sim.bodyTouching(lejos), isFalse,
        reason: 'cayendo en el aire, sin nada cerca');
    expect(sim.bodyContactDepth(lejos), 0);

    sim.dispose();
  });

  test('la lectura entre pasos NO ve un mapa vacío: se limpia al empezar', () {
    final sim = OdeSimulation();
    addGround(sim);
    final caja = addBox(sim, Vector3(0, 0.5, 0));

    // Diez pasos seguidos, leyendo DESPUÉS de cada uno. Si el mapa se
    // limpiara al final del paso, todas estas lecturas darían falso.
    for (var i = 0; i < 10; i++) {
      sim.step(sim.fixedTimestep);
      expect(sim.bodyTouching(caja), isTrue, reason: 'paso $i');
    }

    sim.dispose();
  });

  test('deja de tocar cuando se aparta', () {
    final sim = OdeSimulation();
    addGround(sim);
    final caja = addBox(sim, Vector3(0, 0.5, 0));

    sim.step(sim.fixedTimestep);
    expect(sim.bodyTouching(caja), isTrue);

    // Se teletransporta al aire: en el paso siguiente ya no toca nada.
    sim.setBodyPose(caja, Vector3(0, 30, 0), Quaternion.identity());
    sim.step(sim.fixedTimestep);
    expect(sim.bodyTouching(caja), isFalse);

    sim.dispose();
  });

  test('mismo mecanismo: no se tocan entre sí (el bumper y su chasis)', () {
    final sim = OdeSimulation();
    // SIN suelo: lo único que podrían tocar es el otro.
    final chasis = addBox(sim, Vector3(0, 3, 0));
    final bumper = addBox(sim, Vector3(0.9, 3, 0));
    sim.setBodyCollisionGroup(chasis, 7);
    sim.setBodyCollisionGroup(bumper, 7);

    sim.step(sim.fixedTimestep);

    expect(sim.bodyTouching(chasis), isFalse);
    expect(sim.bodyTouching(bumper), isFalse,
        reason: 'el sensor NO se dispara con su propia pieza');

    // Y con grupos distintos sí, para que el test de arriba no pase por una
    // razón que no es (que las cajas no se solapasen, por ejemplo).
    sim.setBodyCollisionGroup(bumper, 8);
    sim.step(sim.fixedTimestep);
    expect(sim.bodyTouching(chasis), isTrue);
    expect(sim.bodyTouching(bumper), isTrue);

    sim.dispose();
  });

  test('un muro fixed cuenta como contacto (no tiene dBodyID)', () {
    final sim = OdeSimulation();
    final muro = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(2, 3, 0)),
      type: BodyType.fixed,
    );
    sim.createColliders(muro, BoxShape(halfExtents: Vector3(0.5, 2, 5)));

    final caja = addBox(sim, Vector3(1.45, 3, 0));
    sim.setBodyCollisionGroup(caja, 3);

    sim.step(sim.fixedTimestep);

    expect(sim.bodyTouching(caja), isTrue,
        reason: 'chocar contra el mundo es el caso que hay que ver');
    // El muro es fixed: ODE no le da dBodyID y por eso nunca aparece.
    expect(sim.bodyTouching(muro), isFalse);

    sim.dispose();
  });

  test('en pausa el mapa NO se toca: la última foto se conserva', () {
    final sim = OdeSimulation();
    addGround(sim);
    final caja = addBox(sim, Vector3(0, 0.5, 0));

    sim.step(sim.fixedTimestep);
    expect(sim.bodyTouching(caja), isTrue);

    sim.paused = true;
    sim.step(sim.fixedTimestep);
    expect(sim.bodyTouching(caja), isTrue,
        reason: 'step en pausa es no-op: ni limpia ni rellena');

    sim.dispose();
  });
}

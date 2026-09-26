// EL CICLO DE VIDA: crear → destruir → crear, en el mismo proceso.
//
// Deja de ser una curiosidad desde que el mecano se puede CONECTAR a una app:
// la vista del simulador se monta y se desmonta en cada conexión, en cada
// desconexión y cada vez que se navega fuera del editor. O sea que un mundo
// nuevo nace encima de las cenizas del anterior, varias veces por sesión.
//
// Lo que hay que probar no es que `dispose` no reviente, sino que **el
// siguiente mundo SIMULA**. `dispose` llama a `dCloseODE()`, que es un apagado
// GLOBAL de la librería, no de este mundo; si `dInitODE2` no lo levantara otra
// vez, el segundo mundo se construiría sin un solo error y luego dejaría los
// cuerpos flotando. Ese es exactamente el fallo que no se ve.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_lifecycle_test.dart
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

/// Suelta una caja desde y=7 y devuelve a qué altura acabó tras 6 s.
///
/// Es a propósito el MISMO montaje que el primer caso de `ode_simulation_test`
/// —misma caja, mismo suelo, mismos amortiguamientos—, para que el número que
/// se espera aquí no sea uno inventado para esta prueba.
double dejaCaerUnaCaja() {
  final sim = OdeSimulation();
  addGround(sim);

  final body = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, 7, 0)),
    type: BodyType.dynamic_,
    additionalMass: 7.0, // GRAMOS
  );
  sim.createColliders(
    body,
    BoxShape(halfExtents: Vector3(1.5, 1.25, 0.66)),
    material: PhysicsMaterial(friction: 0.8),
  );
  sim.setBodyLinearDamping(body, 0.002);
  sim.setBodyAngularDamping(body, 0.01);

  settle(sim, seconds: 6);

  final (pos, _) = sim.readBodyPose(body);
  sim.dispose();
  return pos.y;
}

void main() {
  setUpAll(exigirOde);

  test('TRES mundos seguidos simulan igual: dCloseODE no deja tierra quemada',
      () {
    // Tres, no dos: con dos, un `dInitODE2` que solo funcionara la primera vez
    // y otro que solo fallara a partir de la tercera darían el mismo verde.
    final alturas = [
      dejaCaerUnaCaja(),
      dejaCaerUnaCaja(),
      dejaCaerUnaCaja(),
    ];

    for (final y in alturas) {
      expect(y.isNaN, isFalse, reason: 'la simulación explotó');
      // Reposando sobre el suelo (semialtura 1 encima de la tapa en y=1).
      expect(y, closeTo(1.25, 0.15),
          reason: 'apoya sobre su semialtura, con la cara del suelo en y=0');
    }
    // Y la MISMA trayectoria — pero no dígito a dígito, y eso hay que
    // decirlo: medido, los tres mundos difieren en ~2.4e-7. No es estado
    // heredado (una fuga daría un error de orden macroscópico, no de la última
    // cifra de un float de 32 bits); es que ODE va en precisión SIMPLE y el
    // orden en que la hash-space recorre los contactos depende de las
    // direcciones que le tocaron al malloc. Es la misma lección que el arnés
    // del mecano ya tenía escrita: «los goldens salen byte a byte» es
    // inalcanzable, y lo exigible es la FORMA.
    //
    // 1e-5 deja pasar eso y sigue siendo mil veces más fino que la tolerancia
    // de arriba, así que una regresión de verdad no se cuela.
    expect(alturas[1], closeTo(alturas[0], 1e-5));
    expect(alturas[2], closeTo(alturas[0], 1e-5));
  });

  test('dispose dos veces no revienta', () {
    // La vista puede desmontarse por dos caminos (desconexión y navegación) y
    // los dos acaban aquí.
    final sim = OdeSimulation();
    sim.dispose();
    expect(sim.dispose, returnsNormally);
  });
}

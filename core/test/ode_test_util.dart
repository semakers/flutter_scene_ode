// Utilidades del banco. Sin Flutter, sin Android, sin qemu: `scene` es Dart
// puro y `tool/build_ode.sh host` produce el libode de esta caja.
//
// El MISMO banco corre en dos sitios: en la VM contra libode.so (el de
// siempre) y en Chrome contra ode.wasm (`flutter test --platform chrome`). Que
// las aserciones no cambien ni una coma entre los dos es justamente lo que
// prueba la paridad del backend de web.
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

export 'dart:math' show pi;

// El arranque cambia según dónde corra el banco: en la VM no hay nada que
// preparar, en el navegador hay que inyectarle los bytes del módulo.
import 'arranque_ode_vm.dart'
    if (dart.library.js_interop) 'arranque_ode_web.dart';

/// La compuerta de todos los archivos del banco: `setUpAll(exigirOde);`.
///
/// Es asíncrona porque en web el módulo hay que descargarlo e instanciarlo. En
/// la VM `ensureAvailable` no espera a nada y devuelve un futuro ya completado,
/// así que el banco de siempre no nota la diferencia.
///
/// NO se salta: FALLA. Un banco que se salta en silencio es exactamente cómo
/// no se entera nadie de que el backend dejó de cargar.
Future<void> exigirOde() async {
  await prepararOde();
  await OdeSimulation.ensureAvailable();
  if (!OdeSimulation.isAvailable) {
    fail(
      'no hay backend de ODE. En la VM: compílalo con `tool/build_ode.sh host` '
      'y exporta ODE_LIBRARY_PATH. En el navegador: corre '
      '`tool/vendor_wasm.sh`. Motivo: ${OdeSimulation.unavailableReason}',
    );
  }
}

/// Nombre viejo, por si queda alguna llamada. Hace lo mismo.
Future<void> skipIfNoOde() => exigirOde();

/// El suelo de todas las escenas de prueba.
///
/// Es una CAJA, no un plano, y a propósito: la pareja que se quiere ejercitar
/// con la llanta es exactamente cylinder-box. Colocado en y = -1 con
/// semialtura 1, así que **su cara superior queda en y = 0** — ese es el cero
/// del que cuelgan todas las alturas esperadas.
int addGround(OdeSimulation sim, {double friction = 0.8}) {
  final handle = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, -1, 0)),
    type: BodyType.fixed,
  );
  sim.createColliders(
    handle,
    BoxShape(halfExtents: Vector3(50, 1, 50)),
    material: PhysicsMaterial(friction: friction),
  );
  return handle;
}

/// Avanza [seconds] de simulación al paso fijo del backend.
void settle(OdeSimulation sim, {double seconds = 5}) {
  final steps = (seconds / sim.fixedTimestep).round();
  for (var i = 0; i < steps; i++) {
    sim.step(sim.fixedTimestep);
  }
}

double velocityOf(OdeSimulation sim, int body) =>
    sim.readBodyLinearVelocity(body).length;

Vector3 principalInertia(OdeSimulation sim, int body) =>
    sim.bodyPrincipalInertia(body);

/// Rotación ACTIVA, la misma que usa el backend. Ojo: `Quaternion.rotate` de
/// vector_math hace la INVERSA, así que un test escrito con ella "pasaría"
/// justo cuando el código está mal.
Vector3 rotateActiveForTest(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transform(v.clone());

// El backend donde no hay NI `dart:ffi` NI `dart:js_interop`.
//
// Desde que web tiene su propio backend de WebAssembly, esta rama ya no le toca
// a ninguna plataforma real: es el `else` del export condicional. Pero sigue
// siendo la que RESUELVE EL ANALIZADOR, así que su superficie pública tiene que
// seguir calcando la de verdad — si aquí falta un miembro, el consumidor se ve
// rojo en el editor aunque compile y corra bien en las seis plataformas.
//
// Misma superficie pública que el de verdad, para que quien lo consuma compile
// igual en todas partes y decida en tiempo de EJECUCIÓN. Preguntar
// `isAvailable` tiene que ser seguro siempre: es lo que decide entre abrir el
// constructor y enseñar la pantalla honesta.
//
// Extiende `BasicSimulation` (del propio contrato) en vez de `PhysicsSimulation`
// por una razón práctica: `PhysicsSimulation` tiene ~38 miembros abstractos y
// reimplementarlos aquí sería un muro de ruido que además habría que mantener
// sincronizado a mano. `BasicSimulation` ya los trae, y de todas formas nadie
// va a llegar a llamarlos: el constructor lanza.
import 'package:scene/physics.dart' as sim;
import 'package:vector_math/vector_math.dart';

import 'ode/ode_telemetry.dart';

export 'ode/ode_telemetry.dart';

class OdeSimulation extends sim.BasicSimulation {
  OdeSimulation({OdeTelemetrySink? telemetry, double telemetryPeriod = 1.0}) {
    throw UnsupportedError(unavailableReason!);
  }

  /// Falso aquí, siempre: esta plataforma no tiene `dart:ffi`. Consultarlo
  /// ANTES de construir es el uso correcto.
  static bool get isAvailable => false;

  /// El gemelo de la cara nativa y la web. Aquí no hay nada que preparar, pero
  /// tiene que existir: el analizador resuelve el barrel por ESTA rama, así que
  /// sin él todo el que la llame se ve rojo en el editor aunque corra bien.
  static Future<void> ensureAvailable() async {}

  static String? get unavailableReason =>
      'ODE no está disponible en esta plataforma: no hay ni dart:ffi ni '
      'dart:js_interop. El constructor del mecano corre con ODE nativo en '
      'Android, iOS, macOS y Windows, y con ODE compilado a WebAssembly en el '
      'navegador.';

  @override
  String get backendName => 'ode-unsupported';

  /// Existen para que el código del consumidor compile en web; no hacen nada.
  OdeTelemetrySink? telemetry;
  double telemetryPeriod = 1.0;
  bool paused = false;

  /// El reloj del mundo. Aquí no corre ninguno, así que se queda en cero.
  double get simTime => 0;

  double hingeAngle(int jointHandle) =>
      throw UnsupportedError(unavailableReason!);

  double hingeAngleRate(int jointHandle) =>
      throw UnsupportedError(unavailableReason!);

  void setBodyCollisionGroup(int bodyHandle, int group) =>
      throw UnsupportedError(unavailableReason!);

  bool bodyTouching(int bodyHandle) =>
      throw UnsupportedError(unavailableReason!);

  double bodyContactDepth(int bodyHandle) =>
      throw UnsupportedError(unavailableReason!);

  // Diagnóstico. Están aquí porque el analizador resuelve el barrel por esta
  // rama: sin ellos, todo el que use los extras se ve rojo en el editor
  // aunque compile y corra bien en Android.
  Vector3 bodyPrincipalInertia(int bodyHandle) =>
      throw UnsupportedError(unavailableReason!);

  double bodyMass(int bodyHandle) =>
      throw UnsupportedError(unavailableReason!);

  Vector3 debugHingeAnchor(int jointHandle) =>
      throw UnsupportedError(unavailableReason!);
}

// La telemetría del backend.
//
// No es un `print` de depuración que sobró: es el instrumento que destrabó el
// spike entero. Tras dos parches fallidos a ciegas, una línea por segundo de
// simulación hizo saltar a la vista las cuatro causas reales (masas en kg,
// contactos internos del mecanismo, damping por-paso y el cuaternión
// invertido). Se queda, y se queda barata de encender.
//
// Cambios respecto al spike:
//  - va detrás de un sink inyectable en vez de `print` incondicional;
//  - dispara por TIEMPO ACUMULADO, no por «cada 240 pasos» (dos constantes
//    clavadas que mentían en cuanto cambiara el dt);
//  - se emite DESPUÉS del step (antes, la línea `t=6.0s` describía t=5.996);
//  - campos nuevos al final, sin reordenar los viejos: las capturas y la
//    crónica del spike citan estos tokens y se quiere poder comparar.

/// Dónde va cada línea. `debugPrint` en la app, un buffer en los tests.
typedef OdeTelemetrySink = void Function(String line);

/// Una foto de un cuerpo dinámico en el instante de emitir.
class OdeBodySample {
  const OdeBodySample({
    required this.handle,
    required this.x,
    required this.y,
    required this.z,
    required this.speed,
    required this.spin,
    required this.sleeping,
  });

  final int handle;
  final double x, y, z;
  final double speed, spin;
  final bool sleeping;

  bool get finite => x.isFinite && y.isFinite && z.isFinite;
}

/// Una foto de un hinge. Los DOS gaps miden cosas distintas y por eso van los
/// dos: [gapRequested] es el viaje de ida y vuelta descriptor→ODE→cuerpos (el
/// ancla que se PIDIÓ, vista desde cada cuerpo) y es lo único que habría cazado
/// el cuaternión invertido, porque aquel bug dejaba los dos cuerpos
/// consistentes entre sí; [gapSolver] es la separación de las anclas que ODE
/// mantiene, o sea violación de la restricción.
class OdeHingeSample {
  const OdeHingeSample({
    required this.handle,
    required this.gapRequested,
    required this.gapSolver,
    required this.angle,
    required this.rate,
  });

  final int handle;
  final double gapRequested, gapSolver;
  final double angle, rate;
}

/// Formatea una línea de telemetría. Puro: los tests lo ejercitan sin ODE.
String formatOdeTelemetry({
  required double simTime,
  required double maxPenetration,
  required int maxContacts,
  required List<OdeBodySample> bodies,
  required List<OdeHingeSample> hinges,
}) {
  final b = StringBuffer('ode t=${simTime.toStringAsFixed(1)}s');
  b.write(' pen=${maxPenetration.toStringAsFixed(3)}');
  b.write(' nc=$maxContacts');
  for (final s in bodies) {
    b.write(
      '\n   [${s.handle}] y=${s.y.toStringAsFixed(2)} '
      '|v|=${s.speed.toStringAsFixed(2)} |w|=${s.spin.toStringAsFixed(2)} '
      '${s.sleeping ? 'zZ' : 'ON'} '
      '@(${s.x.toStringAsFixed(2)},${s.z.toStringAsFixed(2)})',
    );
  }
  for (final h in hinges) {
    b.write(
      '\n   hinge[${h.handle}] '
      'gap=${h.gapRequested.toStringAsFixed(3)}/${h.gapSolver.toStringAsFixed(3)} '
      'a=${_degrees(h.angle).toStringAsFixed(1)} '
      'w=${h.rate.toStringAsFixed(2)}',
    );
  }
  return b.toString();
}

double _degrees(double radians) => radians * 180.0 / 3.141592653589793;

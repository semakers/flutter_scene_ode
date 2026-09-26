// LA MARCHA del Otto en la réplica pura de ODE: ¿avanza, gira, aguanta?
//
// Reproduce lo que manda el `.npg` de `gen_otto.py`: la senoidal del Otto de
// verdad muestreada en 12 pasos, con la cuantización del cable (0..180 → 0..99
// → 0..1·π) y una espera por paso. El juez es el desplazamiento del cuerpo y
// que siga de pie; una foto no vale.
//
// Correr en Chrome: ver `nairda-otto-bipedo`.
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:vector_math/vector_math.dart';

import '../ode_test_util.dart';
import 'otto_replica.dart';

/// Lo que llega a la junta por una orden POSITION de [deg] grados: el bloque
/// mapea 0..180 → 0..99 y trunca; el mecano hace raw/99·π.
/// 0 = la orden entera truncada tal cual (lo que hace hoy el generador);
/// 1 = el entero cuyo nivel cuantizado queda MÁS CERCA del ángulo pedido;
/// 2 = sin cuantizar (imposible en la app; solo para aislar el efecto).
int modoCmd = 0;
double cmd(double deg) {
  switch (modoCmd) {
    case 2:
      return radians(deg);
    case 1:
      var mejor = 0, err = 1e9;
      for (var d = 0; d <= 180; d++) {
        final e = ((d * 99 ~/ 180) * 180 / 99 - deg).abs();
        if (e < err) {
          err = e;
          mejor = d;
        }
      }
      return (mejor * 99 ~/ 180) / 99.0 * math.pi;
    default:
      return (deg.clamp(0, 180).toInt() * 99 ~/ 180) / 99.0 * math.pi;
  }
}

class Marcha {
  Marcha({
    required this.hipAmp,
    required this.ankleAmp,
    required this.tiptoe,
    required this.phaseMs,
    this.turnAmp = 10,
    this.alterno = true,
    this.hipHome = 30,
    this.ankleHome = 24,
    this.pasos = 12,
    this.trimIzq = 0,
  });
  final double hipAmp, ankleAmp, tiptoe, turnAmp, hipHome, ankleHome, trimIzq;
  final int phaseMs, pasos;
  final bool alterno;

  /// (cadera_izq, cadera_der, tobillo_izq, tobillo_der) en grados Nairda.
  List<List<double>> senoidal(double ampIzq, double ampDer, double faseTobillo) {
    final out = <List<double>>[];
    for (var k = 0; k < pasos; k++) {
      final th = 2 * math.pi * k / pasos;
      final fase = math.sin(th + radians(faseTobillo));
      final double al, ar;
      if (alterno) {
        al = ankleHome + (ankleAmp + tiptoe) * fase;
        ar = ankleHome + (ankleAmp - tiptoe) * fase;
      } else {
        al = ankleHome + ankleAmp * fase + tiptoe;
        ar = ankleHome + ankleAmp * fase - tiptoe;
      }
      out.add([
        hipHome + ampIzq * math.sin(th),
        hipHome + ampDer * math.sin(th),
        al,
        ar,
      ]);
    }
    return out;
  }

  List<List<double>> gait(String cual) => switch (cual) {
        // +90 es la fase que lleva hacia +Z, a donde miran los ojos (MEDIDO).
        'adelante' => senoidal(hipAmp - trimIzq, hipAmp, 90),
        'atras' => senoidal(hipAmp, hipAmp, -90),
        'izquierda' => senoidal(hipAmp, turnAmp, 90),
        'derecha' => senoidal(turnAmp, hipAmp, 90),
        'izquierda-' => senoidal(hipAmp, turnAmp, -90),
        'derecha-' => senoidal(turnAmp, hipAmp, -90),
        _ => throw ArgumentError(cual),
      };

  @override
  String toString() =>
      'hip±$hipAmp ank±$ankleAmp tip$tiptoe ${alterno ? "alt" : "fijo"} ${phaseMs}ms';
}

class Resultado {
  Resultado(this.dx, this.dz, this.dyaw, this.dePie, this.alto);
  final double dx, dz, dyaw, alto;
  final bool dePie;
  @override
  String toString() =>
      'dx=${dx.toStringAsFixed(2)} dz=${dz.toStringAsFixed(2)} '
      'giro=${dyaw.toStringAsFixed(0)}° ${dePie ? "DE PIE" : "CAÍDO"} y=${alto.toStringAsFixed(2)}';
}

(Vector3, double) cuerpo(OdeSimulation sim, Otto o) {
  final (p, q) = sim.readBodyPose(o.byId['cuerpo']!.handle);
  final fwd = act(q, Vector3(0, 0, 1));
  return (p, degrees(math.atan2(fwd.x, fwd.z)));
}

void manda(Otto o, List<double> deg) {
  final ids = ['cadera_izq', 'cadera_der', 'tobillo_izq', 'tobillo_der'];
  for (var i = 0; i < 4; i++) {
    o.byIdBisagra(ids[i]).target = cmd(deg[i]);
  }
}

Resultado corre(Marcha m, String cual, {int ciclos = 4, bool traza = false, bool espejo = false, int k0 = 0, List<double>? yawPorCiclo, double asiento = 2.0}) {
  final sim = OdeSimulation();
  addGround(sim, friction: 0.8);
  final o = buildOtto(hipHomeDeg: m.hipHome, ankleHomeDeg: m.ankleHome, espejo: espejo);
  spawn(sim, o);
  run(sim, o, 1.0);
  // La rampa de arranque del programa: 10 escalones de 300 ms.
  for (var k = 1; k <= 10; k++) {
    manda(o, [m.hipHome * k / 10, m.hipHome * k / 10, m.ankleHome * k / 10, m.ankleHome * k / 10]);
    run(sim, o, 0.3);
  }
  run(sim, o, asiento);
  final (p0, yaw0) = cuerpo(sim, o);
  final pasos0 = m.gait(cual);
  final pasos = [...pasos0.sublist(k0), ...pasos0.sublist(0, k0)];
  for (var c = 0; c < ciclos; c++) {
    for (final paso in pasos) {
      manda(o, paso);
      run(sim, o, m.phaseMs / 1000);
    }
    if (yawPorCiclo != null) {
      var y = cuerpo(sim, o).$2 - yaw0;
      while (y > 180) y -= 360;
      while (y < -180) y += 360;
      yawPorCiclo.add(y);
    }
    if (traza) {
      final (p, yaw) = cuerpo(sim, o);
      print('    ciclo ${c + 1}: (${p.x.toStringAsFixed(2)}, ${p.z.toStringAsFixed(2)}) yaw=${yaw.toStringAsFixed(0)} ${estado(sim, o)}');
    }
  }
  // Y el reposo, que el programa manda al soltar el mando.
  manda(o, [m.hipHome, m.hipHome, m.ankleHome, m.ankleHome]);
  run(sim, o, 1.0);
  final (p1, yaw1) = cuerpo(sim, o);
  final (_, q) = sim.readBodyPose(o.byId['cuerpo']!.handle);
  final up = act(q, Vector3(0, 1, 0));
  var dyaw = yaw1 - yaw0;
  while (dyaw > 180) dyaw -= 360;
  while (dyaw < -180) dyaw += 360;
  final r = Resultado(p1.x - p0.x, p1.z - p0.z, dyaw, up.y > 0.85 && p1.y > 6.0, p1.y);
  sim.dispose();
  return r;
}

void main() {
  setUpAll(exigirOde);

  // LA CONFIGURACIÓN ENTREGADA en `~/dev/otto/gen_otto.py` (2026-09-01), con
  // cuatro arranques distintos porque la marcha recta es caótica: lo que se
  // exige es que sea REPETIBLE, no un número exacto. Si se toca la marcha
  // allí, se toca aquí.
  test('la marcha entregada: recta y repetible, y los giros al lado que dicen', () {
    final m = Marcha(hipAmp: 30, ankleAmp: 15, tiptoe: 4, phaseMs: 500, alterno: false, trimIzq: 8);
    for (final cual in ['adelante', 'atras', 'izquierda', 'derecha']) {
      final linea = StringBuffer('$m ${cual.padRight(9)}');
      for (final asiento in [2.0, 2.15, 2.3, 2.45]) {
        final r = corre(m, cual, ciclos: 6, k0: 3, asiento: asiento);
        linea.write(' | dz=${r.dz.toStringAsFixed(0).padLeft(3)} dx=${r.dx.toStringAsFixed(0).padLeft(3)} giro=${r.dyaw.toStringAsFixed(0).padLeft(4)}${r.dePie ? "" : " CAÍDO"}');
        expect(r.dePie, isTrue, reason: '$cual se cae');
        switch (cual) {
          case 'adelante':
            expect(r.dz, greaterThan(10), reason: 'adelante avanza hacia +Z');
            expect(r.dyaw.abs(), lessThan(45));
          case 'atras':
            expect(r.dz, lessThan(-10));
            expect(r.dyaw.abs(), lessThan(45));
          // En la RÉPLICA la cadera 'izq' sigue en −X (es la derecha real):
          // 'izquierda' aquí es el giro a la derecha de la app, y al revés.
          case 'izquierda':
            expect(r.dyaw, lessThan(-30));
          case 'derecha':
            expect(r.dyaw, greaterThan(30));
        }
      }
      print(linea);
    }
  });
}

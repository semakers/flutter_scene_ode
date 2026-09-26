// RÉPLICA del Otto de `~/dev/otto/gen_otto.py` en ODE puro, sin Flutter.
//
// Misma geometría (cajas de las specs), mismas masas en gramos, un cuerpo por
// nodo soldable, soldaduras `dFixed`, un solo grupo de colisión para todo el
// mecanismo y la misma ley del servo (`servo_controller.dart`). Sirve para
// preguntarle a la física en segundos lo que en el build web cuesta ocho
// minutos: qué secuencia de arranque llega a la pose de reposo con los pies
// planos y por qué la otra se atasca.
import 'dart:math' as math;

import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

// --- constantes calcadas del generador ------------------------------------
const hipX = 2.55, hipY = 4.90, ankleY = 1.75;
const cell = 1.5, thick = 0.3, floorGap = 0.02;
final servoShaft = Vector3(-0.2316, 2.5556, -0.0142);
final caseC = Vector3(0.1812, 1.2886, -0.0161);
final caseH = Vector3(1.5062, 1.2681, 0.6650);
final hornC = Vector3(-0.2310, 2.9414, 0.0001);
final hornH = Vector3(1.9396, 0.3858, 0.5255);
final ultraC = Vector3(0.0, 0.6205, 0.0);
final ultraH = Vector3(1.1036, 0.6494, 2.3049);
const massCase = 7.0, massHorn = 2.0, massCell = 1.82, massUltra = 4.8;
const frictionServo = 0.8, frictionPlate = 0.6;
// servo_spec: topes, ley P, banda muerta.
const lo = -0.15, hi = 3.10, kp = 8.0, maxSpeed = 2.0;

/// La banda muerta del servo (`ServoSpec.deadBand`). Mutable para poder
/// compararla en el banco de la marcha.
double deadBand = 0.05;

Quaternion qAxis(Vector3 axis, double ang) =>
    Quaternion.axisAngle(axis.normalized(), ang);

/// Rotación ACTIVA. OJO: `Quaternion.rotated` de vector_math aplica la
/// CONJUGADA (gira el marco, no el vector): con +90° sobre X manda (0,1,0) a
/// (0,0,-1) mientras `asRotationMatrix` la manda a (0,0,1). Toda la réplica
/// pasa por aquí para casar con las matrices que usa el rig.
Vector3 act(Quaternion q, Vector3 v) => q.conjugated().rotated(v);

/// Una caja rígida del mundo: centro, rotación, semiejes, masa.
class Caja {
  Caja(this.id, this.center, this.rot, this.half, this.mass, this.friction);
  final String id;
  Vector3 center;
  Quaternion rot;
  final Vector3 half;
  final double mass;
  final double friction;
  int handle = -1;

  void preRotate(Vector3 axis, double ang, Vector3 point) {
    final q = qAxis(axis, ang);
    center = point + act(q, center - point);
    rot = (q * rot)..normalize();
  }


  double get minY {
    final cols = [
      act(rot, Vector3(half.x, 0, 0)),
      act(rot, Vector3(0, half.y, 0)),
      act(rot, Vector3(0, 0, half.z)),
    ];
    final hy = cols.fold(0.0, (s, c) => s + c.y.abs());
    return center.y - hy;
  }
}

class Bisagra {
  Bisagra(this.id, this.parent, this.child, this.pivot, this.axisWorld);
  final String id;
  final Caja parent, child;
  Vector3 pivot;
  Vector3 axisWorld; // el eje de la SPEC (−Y del servo), no el de la orden
  int handle = -1;
  late Vector3 anchorA, anchorB, axisA, axisB;
  double target = 0;
  double stall = 17658, brake = 17658;

  void preRotate(Vector3 axis, double ang, Vector3 point) {
    final q = qAxis(axis, ang);
    pivot = point + act(q, pivot - point);
    axisWorld = act(q, axisWorld);
  }
}

class Otto {
  final cajas = <Caja>[];
  final bisagras = <Bisagra>[];
  final soldaduras = <(Caja, Caja)>[];
  final byId = <String, Caja>{};

  Caja add(Caja c) {
    cajas.add(c);
    byId[c.id] = c;
    return c;
  }

  /// Un servo: case + horn + bisagra. Devuelve (case, horn, bisagra).
  (Caja, Caja, Bisagra) servo(String id, Quaternion mount, Vector3 shaftWorld) {
    final pos = shaftWorld - act(mount, servoShaft);
    final c = add(Caja('${id}_case', pos + act(mount, caseC), mount, caseH,
        massCase, frictionServo));
    final h = add(Caja('${id}_horn', pos + act(mount, hornC), mount, hornH,
        massHorn, frictionServo));
    final b = Bisagra(id, c, h, shaftWorld.clone(),
        act(mount, Vector3(0, -1, 0)));
    bisagras.add(b);
    return (c, h, b);
  }

  Caja plate(String id, int cols, int rows, Vector3 pos, Quaternion q) => add(
      Caja(id, pos, q, Vector3(cols * cell / 2, thick / 2, rows * cell / 2),
          massCell * cols * rows, frictionPlate));

  void weld(String a, String b) => soldaduras.add((byId[a]!, byId[b]!));

  Bisagra byIdBisagra(String id) => bisagras.firstWhere((b) => b.id == id);
}

/// Construye el Otto tal como lo guarda el generador, con las pre-rotaciones
/// [hipHomeDeg] (guiñada de cadera) y [ankleHomeDeg] (balanceo del pie).
Otto buildOtto({double hipHomeDeg = 30, double ankleHomeDeg = 24,
    bool tumbarSobreLosPies = false, bool espejo = false}) {
  final o = Otto();
  final hipRot = qAxis(Vector3(0, 0, 1), math.pi);
  final ankleRot = qAxis(Vector3(1, 0, 0), math.pi / 2);
  // El lado derecho EN ESPEJO: mismo eje de giro y mismo sentido de la orden,
  // pero la caja del servo (que no está centrada en su eje) cae al otro lado.
  // Con los dos servos montados igual, las cuatro cajas cuelgan hacia −X y el
  // robot es quiral: anda en curva.
  final hipRotR = espejo ? qAxis(Vector3(1, 0, 0), math.pi) : hipRot;
  final ankleRotR = espejo
      ? (qAxis(Vector3(0, 0, 1), math.pi) * ankleRot..normalize())
      : ankleRot;

  final (hipLc, _, hipL) = o.servo('cadera_izq', hipRot, Vector3(-hipX, hipY, 0));
  final (hipRc, _, hipR) = o.servo('cadera_der', hipRotR, Vector3(hipX, hipY, 0));
  final bodyTop = math.max(
      hipLc.center.y + (act(hipRot, Vector3(0, caseH.y, 0))).y.abs(),
      hipRc.center.y + (act(hipRot, Vector3(0, caseH.y, 0))).y.abs());
  o.plate('cuerpo', 6, 2, Vector3(0, bodyTop + thick / 2, 0), Quaternion.identity());
  final headY = bodyTop + thick + 1.5;
  o.plate('cabeza', 4, 2, Vector3(0, headY, 0), qAxis(Vector3(1, 0, 0), math.pi / 2));
  final ultraRot =
      (qAxis(Vector3(0, 0, 1), math.pi / 2) * qAxis(Vector3(1, 0, 0), math.pi / 2))
        ..normalize();
  final ultraCenter = Vector3(0, headY, 0.9);
  o.add(Caja('ultrasonico', ultraCenter, ultraRot, ultraH, massUltra, frictionPlate));
  o.weld('cuerpo', 'cadera_izq_case');
  o.weld('cuerpo', 'cadera_der_case');
  o.weld('cuerpo', 'cabeza');
  o.weld('cabeza', 'ultrasonico');

  for (final (side, sx, hip) in [('izq', -1.0, hipL), ('der', 1.0, hipR)]) {
    final hx = sx * hipX;
    final leg = o.plate('pierna_$side', 1, 2, Vector3(hx, hipY - 1.5, 0),
        qAxis(Vector3(1, 0, 0), math.pi / 2));
    final aRot = side == 'der' ? ankleRotR : ankleRot;
    final hRot = side == 'der' ? hipRotR : hipRot;
    final (ankC, ankH, ank) = o.servo('tobillo_$side', aRot, Vector3(hx, ankleY, 0));
    final foot = o.plate('pie_$side', 3, 4, Vector3(hx, thick / 2, 0), Quaternion.identity());
    // La orden crece sobre +Y local del servo (ODE niega el ángulo).
    final ankleCmdAxis = act(aRot, Vector3(0, 1, 0));
    final hipCmdAxis = act(hRot, Vector3(0, 1, 0));
    foot.preRotate(ankleCmdAxis, -radians(ankleHomeDeg), Vector3(hx, ankleY, 0));
    for (final c in [leg, ankC, ankH, foot]) {
      c.preRotate(hipCmdAxis, -radians(hipHomeDeg), Vector3(hx, hipY, 0));
    }
    ank.preRotate(hipCmdAxis, -radians(hipHomeDeg), Vector3(hx, hipY, 0));
    o.weld('cadera_${side}_horn', 'pierna_$side');
    o.weld('pierna_$side', 'tobillo_${side}_case');
    o.weld('tobillo_${side}_horn', 'pie_$side');
  }

  if (tumbarSobreLosPies) {
    // Pose alternativa: el conjunto entero girado +ankleHome sobre el eje del
    // tobillo IZQUIERDO, para que ese pie quede plano en el suelo.
    final ankL = o.bisagras.firstWhere((b) => b.id == 'tobillo_izq');
    final axis = ankL.axisWorld.clone()..negate();
    for (final c in o.cajas) {
      c.preRotate(axis, radians(ankleHomeDeg), ankL.pivot);
    }
    for (final b in o.bisagras) {
      b.preRotate(axis, radians(ankleHomeDeg), ankL.pivot);
    }
  }

  final minY = o.cajas.map((c) => c.minY).reduce(math.min);
  final lift = floorGap - minY;
  for (final c in o.cajas) {
    c.center.y += lift;
  }
  for (final b in o.bisagras) {
    b.pivot.y += lift;
  }
  return o;
}

/// Mete el Otto en la simulación; devuelve el handle del suelo.
void spawn(OdeSimulation sim, Otto o, {int group = 7}) {
  for (final c in o.cajas) {
    c.handle = sim.createBody(
      target: SimplePoseTarget(translation: c.center.clone(), rotation: c.rot.clone()),
      type: BodyType.dynamic_,
      additionalMass: c.mass,
    );
    sim.createColliders(c.handle, BoxShape(halfExtents: c.half.clone()),
        material: PhysicsMaterial(friction: c.friction));
    sim.setBodyCollisionGroup(c.handle, group);
  }
  for (final (a, b) in o.soldaduras) {
    sim.createJoint(FixedJointDesc(bodyA: a.handle, bodyB: b.handle));
  }
  for (final b in o.bisagras) {
    final invA = b.parent.rot.conjugated();
    final invB = b.child.rot.conjugated();
    b.anchorA = act(invA, b.pivot - b.parent.center);
    b.anchorB = act(invB, b.pivot - b.child.center);
    b.axisA = act(invA, b.axisWorld)..normalize();
    b.axisB = act(invB, b.axisWorld)..normalize();
    b.handle = sim.createJoint(RevoluteJointDesc(
      bodyA: b.parent.handle,
      bodyB: b.child.handle,
      localAnchorA: b.anchorA,
      localAnchorB: b.anchorB,
      localAxisA: b.axisA,
      localAxisB: b.axisB,
      lowerLimit: lo,
      upperLimit: hi,
      motorTargetVelocity: 0,
      motorMaxForce: b.stall,
    ));
  }
}

/// La ley del servo de `servo_controller.dart`, un tick.
/// El mecanismo entero, despierto. Con el autodisable puesto, los motores de
/// ODE NO despiertan cuerpos dormidos: sin esto el Otto, ya asentado y
/// dormido tras la rampa, ignoraba la marcha entera (dx = dz = 0.00 exactos).
/// `ServoController.fixedUpdate` hace lo mismo con `wakeMechanism()`.
void despierta(OdeSimulation sim, Otto o) {
  for (final c in o.cajas) {
    sim.wakeBody(c.handle);
  }
}

void servoTick(OdeSimulation sim, Otto o, Bisagra b) {
  final angle = sim.hingeAngle(b.handle);
  final target = b.target.clamp(lo + 2 * deadBand, hi - 2 * deadBand);
  final error = target - angle;
  final double vel, fmax;
  if (error.abs() < deadBand) {
    vel = 0;
    fmax = b.brake;
  } else {
    vel = (kp * error).clamp(-maxSpeed, maxSpeed);
    fmax = b.stall;
    despierta(sim, o);
  }
  sim.updateJoint(
      b.handle,
      RevoluteJointDesc(
        bodyA: b.parent.handle,
        bodyB: b.child.handle,
        localAnchorA: b.anchorA,
        localAnchorB: b.anchorB,
        localAxisA: b.axisA,
        localAxisB: b.axisB,
        lowerLimit: lo,
        upperLimit: hi,
        motorTargetVelocity: vel,
        motorMaxForce: fmax,
      ));
}

void run(OdeSimulation sim, Otto o, double seconds) {
  final steps = (seconds / sim.fixedTimestep).round();
  for (var i = 0; i < steps; i++) {
    for (final b in o.bisagras) {
      servoTick(sim, o, b);
    }
    sim.step(sim.fixedTimestep);
  }
}

String estado(OdeSimulation sim, Otto o) {
  final sb = StringBuffer();
  for (final b in o.bisagras) {
    sb.write('${b.id.replaceAll('cadera_', 'C').replaceAll('tobillo_', 'T')}='
        '${degrees(sim.hingeAngle(b.handle)).toStringAsFixed(1)} ');
  }
  for (final id in ['pie_izq', 'pie_der', 'cuerpo']) {
    final (p, q) = sim.readBodyPose(o.byId[id]!.handle);
    final up = act(q, Vector3(0, 1, 0));
    sb.write('$id y=${p.y.toStringAsFixed(2)} up=(${up.x.toStringAsFixed(2)},'
        '${up.y.toStringAsFixed(2)},${up.z.toStringAsFixed(2)}) ');
  }
  return sb.toString();
}

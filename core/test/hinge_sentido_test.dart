// EL SENTIDO del hinge, medido sobre el CUERPO y no sobre la lectura.
//
// `ode_simulation_test.dart` ya vigila que velocidad positiva → ángulo
// creciente. Lo que NO decía nadie es hacia dónde gira el cuerpo B cuando el
// ángulo crece. ODE lo niega por dentro (`theta = -theta` en
// `getHingeAngleFromRelativeQuat`), así que:
//
//   ángulo +θ  ⇒  B ha girado −θ alrededor de `localAxisA` (regla de la mano
//                 derecha), o lo que es lo mismo, A ha girado +θ respecto a B.
//
// El generador del Otto (`~/dev/otto/gen_otto.py`) supuso lo contrario y el
// robot nació con los tobillos a 52° en vez de a 0°: los pies nunca tocaban
// el suelo con toda la planta. Este test es para que no vuelva a pasar a
// nadie que monte una pieza «girada −θ para que la orden θ la enderece».
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

void main() {
  setUpAll(exigirOde);

  test('ángulo +θ del hinge = el cuerpo B gira −θ alrededor de localAxisA', () {
    final sim = OdeSimulation();
    final parent = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
      type: BodyType.fixed,
    );
    final child = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
      type: BodyType.dynamic_,
      additionalMass: 2.0,
    );
    sim.createColliders(child, BoxShape(halfExtents: Vector3(1.9, 0.39, 0.53)));
    sim.setBodyGravityScale(child, 0);
    final joint = sim.createJoint(RevoluteJointDesc(
      bodyA: parent,
      bodyB: child,
      localAxisA: Vector3(0, 0, 1),
      localAxisB: Vector3(0, 0, 1),
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3.zero(),
      motorTargetVelocity: 2.0,
      motorMaxForce: 1766.0,
    ));
    settle(sim, seconds: 0.5);
    final ang = sim.hingeAngle(joint);
    final (_, q) = sim.readBodyPose(child);
    final ex = rotateActiveForTest(q, Vector3(1, 0, 0));
    printOnFailure('hingeAngle=$ang  +X del hijo=$ex');
    expect(ang, closeTo(1.0, 0.05));
    // Girado −1 rad sobre +Z, el +X del hijo apunta a (cos 1, −sin 1, 0).
    expect(ex.x, closeTo(0.5403, 0.02));
    expect(ex.y, closeTo(-0.8415, 0.02),
        reason: 'si sale +0.84, ODE (o el backend) cambió de convención y hay '
            'que revisar todo lo que monta piezas pre-giradas');
    sim.dispose();
  });
}

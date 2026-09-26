// LA COMPUERTA. Se corre antes que nada.
//
// La llanta del motor DC es un CylinderShape, y el cilindro trae una trampa que
// no se anuncia sola: el contrato de `scene` alinea el cilindro a su **Y**
// local ("A cylinder aligned with the local Y axis", shape.dart:43) y ODE lo
// alinea a su **Z** local. Si esa rotación falta, el cilindro sale girado 90°
// respecto a lo que pidió quien lo montó — y la simulación sigue corriendo tan
// tranquila, sin un solo error.
//
// Lo que discrimina es a qué ALTURA descansa, y conviene tener clara la
// geometría antes de leer los números: la llanta es un DISCO (radio 1.589,
// semialtura 0.636), o sea más ancha que alta. Un disco es estable en las dos
// posturas, así que no hay «se tumba solo» que valga:
//
//   eje VERTICAL   -> apoya en su cara plana, centro a y = halfHeight = 0.636
//   eje HORIZONTAL -> apoya en su canto,      centro a y = radius     = 1.589
//
// Por eso hacen falta los dos casos: uno prueba que la rotación se aplica, y el
// otro que se aplica en el sentido correcto. Con un solo caso, una rotación
// invertida pasaría desapercibida.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_cylinder_test.dart
// El .so del host lo produce `tool/build_ode.sh host`. No hace falta Android,
// ni emulador, ni qemu: `scene` es Dart puro.
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

// Las medidas de la llanta del motor DC, tomadas del GLB.
const kRadius = 1.5894;
const kHalfHeight = 0.6362;
const kWheelGrams = 8.0;

void main() {
  setUpAll(skipIfNoOde);

  test('sin localPose el eje del cilindro es el Y del contrato (queda de pie)',
      () {
    final sim = OdeSimulation();
    addGround(sim);

    final body = dropCylinder(sim, localPose: null);
    settle(sim, seconds: 6);

    final (pos, rot) = sim.readBodyPose(body);
    final axis = rotateActiveForTest(rot, Vector3(0, 1, 0));
    printOnFailure('pose final: $pos  eje: $axis');

    expect(
      axis.y.abs(),
      greaterThan(0.9),
      reason: 'con localPose identidad el eje del shape es el Y del cuerpo, '
          'así que tiene que quedar VERTICAL',
    );
    expect(
      pos.y,
      closeTo(kHalfHeight, 0.06),
      reason: 'de pie apoya en su SEMIALTURA ($kHalfHeight). Si sale ~$kRadius '
          'está tumbado: ODE lo alineó a su Z y falta la rotación Y→Z de '
          'createColliders',
    );

    sim.dispose();
  });

  test('con el localPose de la llanta el eje queda horizontal y rueda', () {
    // Ésta es la configuración REAL del motor DC: el eje de `wheel` no apunta
    // al Y del cuerpo sino a su Z, y el ensamblador lo expresa con un
    // localPose rotado. Es el caso que de verdad hay que proteger.
    final sim = OdeSimulation();
    addGround(sim);

    final body = dropCylinder(sim, localPose: wheelLocalPose());
    settle(sim, seconds: 6);

    final (pos, rot) = sim.readBodyPose(body);
    // El eje del shape (Y) pasa por el localPose antes de llegar al cuerpo.
    final axisLocal = rotateActiveForTest(
      Quaternion.axisAngle(Vector3(1, 0, 0), pi / 2),
      Vector3(0, 1, 0),
    );
    final axis = rotateActiveForTest(rot, axisLocal);
    printOnFailure('pose final: $pos  eje: $axis');

    expect(
      axis.y.abs(),
      lessThan(0.15),
      reason: 'el eje tiene que quedar HORIZONTAL: es una rueda',
    );
    expect(
      pos.y,
      closeTo(kRadius, 0.06),
      reason: 'tumbada apoya sobre su RADIO ($kRadius). Si sale ~$kHalfHeight '
          'la rotación Y→Z se está aplicando al revés',
    );
    expect(
      sim.isBodySleeping(body) || velocityOf(sim, body) < 0.05,
      isTrue,
      reason: 'tiene que acabar quieta',
    );

    sim.dispose();
  });

  test('la rueda RUEDA cuando la empujan, y no atraviesa el suelo', () {
    final sim = OdeSimulation();
    addGround(sim);
    final body = dropCylinder(sim, localPose: wheelLocalPose());
    settle(sim, seconds: 4);

    final before = sim.readBodyPose(body).$1.clone();
    // Empujón a lo largo de X, perpendicular al eje (que está en Z).
    sim.setBodyLinearVelocity(body, Vector3(6, 0, 0));
    settle(sim, seconds: 3);
    final after = sim.readBodyPose(body).$1;

    printOnFailure('antes: $before   después: $after');
    expect((after.x - before.x).abs(), greaterThan(2.0),
        reason: 'empujada tiene que recorrer camino');
    expect(after.y, greaterThan(kRadius - 0.15),
        reason: 'no puede hundirse en el suelo: sin la pareja cylinder-box '
            'nativa, dCollide devolvería 0 EN SILENCIO y lo atravesaría');

    sim.dispose();
  });

  test('la inercia de la llanta sobre su eje es ½mr², no la transversal', () {
    // Sin esto, la próxima «simplificación» que borre el dMassRotate y deje
    // direction=2 a secas se cuela sin ruido y con un 39 % menos de inercia:
    // el arranque del motor deja de tardar lo que dice la aritmética.
    final sim = OdeSimulation();
    final body = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: kWheelGrams,
    );
    sim.createColliders(
      body,
      const CylinderShape(radius: kRadius, halfHeight: kHalfHeight),
      localPose: wheelLocalPose(),
    );

    final expected = 0.5 * kWheelGrams * kRadius * kRadius; // 10.10 g·u²
    final inertia = principalInertia(sim, body);
    printOnFailure('tensor diagonal leído de vuelta: $inertia');

    expect(sim.bodyMass(body), closeTo(kWheelGrams, 1e-3),
        reason: 'la masa se pide en GRAMOS y se toma como TOTAL');
    // El eje de giro quedó en Z del cuerpo: ahí tiene que estar el ½mr².
    expect(
      inertia.z,
      closeTo(expected, expected * 0.05),
      reason: 'sobre el eje de giro debe valer ½mr² = $expected. Si sale ~6.1 '
          'es la inercia TRANSVERSAL: falta dMassRotate tras '
          'dMassSetCylinderTotal',
    );

    sim.dispose();
  });

  test('las cápsulas no se cuelan: lanzan con un motivo legible', () {
    final sim = OdeSimulation();
    final body = sim.createBody(
      target: SimplePoseTarget(),
      type: BodyType.dynamic_,
      additionalMass: 1.0,
    );
    expect(
      () => sim.createColliders(
        body,
        const CapsuleShape(radius: 1, halfHeight: 1),
      ),
      throwsA(isA<UnsupportedError>().having(
        (e) => e.message, 'message', contains('libccd'))),
      reason: 'sin libccd la pareja capsule-cylinder no existe y atravesaría '
          'la llanta en silencio: mejor un error ruidoso',
    );
    sim.dispose();
  });
}

/// Suelta un cilindro con las medidas de la llanta desde y = 5.
int dropCylinder(OdeSimulation sim, {required Matrix4? localPose}) {
  final body = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
    type: BodyType.dynamic_,
    additionalMass: kWheelGrams, // GRAMOS
  );
  sim.createColliders(
    body,
    const CylinderShape(radius: kRadius, halfHeight: kHalfHeight),
    material: PhysicsMaterial(friction: 0.25),
    localPose: localPose,
  );
  sim.setBodyLinearDamping(body, 0.002);
  sim.setBodyAngularDamping(body, 0.01);
  return body;
}

/// El localPose de la llanta: manda el eje del shape (Y) al Z del cuerpo.
Matrix4 wheelLocalPose() => Matrix4.compose(
      Vector3.zero(),
      Quaternion.axisAngle(Vector3(1, 0, 0), pi / 2),
      Vector3.all(1),
    );

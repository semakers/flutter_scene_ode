// Banco del backend, sin teléfono: `scene` es Dart puro y el libode del host
// lo produce `tool/build_ode.sh host`.
//
//   ODE_LIBRARY_PATH=<...>/libode.so flutter test
//
// Y el MISMO banco contra el módulo de WebAssembly:
//
//   CHROME_EXECUTABLE=<...> flutter test --platform chrome
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

void main() {
  // La compuerta común. Este fichero llevaba la suya propia en línea —la
  // «compuerta divergente asumida» que anotaba ode_test_util.dart— y ya no:
  // dos compuertas para lo mismo son dos sitios donde equivocarse, y la de
  // aquí no sabía preparar el módulo de web.
  setUpAll(exigirOde);

  test('el .so cargado es single precision (guardia de ABI)', () {
    // Si esto pasa es que dCheckConfiguration dijo que sí: el constructor lanza
    // en caso contrario. Un .so en doble precisión no daría error de enlace,
    // leería basura, y esto es lo único que lo caza.
    final sim = OdeSimulation();
    expect(sim.backendName, 'ode');
    sim.dispose();
  });

  test('una caja cae, aterriza sobre el suelo y se DUERME', () {
    final sim = OdeSimulation();
    addGround(sim);

    final body = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 7, 0)),
      type: BodyType.dynamic_,
      additionalMass: 7.0, // GRAMOS: la carcasa de un SG90
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
    printOnFailure('pose final: $pos');
    expect(pos.y, closeTo(1.25, 0.15),
        reason: 'apoya sobre su semialtura, con la cara del suelo en y=0');
    expect(sim.isBodySleeping(body), isTrue,
        reason: 'el autodisable es lo que hace viable el Redmi 7: si no '
            'duerme, la escena nunca deja de costar');
    sim.dispose();
  });

  group('hinge', () {
    test('el motor lleva la junta al ángulo pedido', () {
      final sim = OdeSimulation();
      final (:parent, :child, :joint) = buildHinge(sim, targetAngle: 1.0);

      // Controlador P mínimo, como el del servo.
      for (var i = 0; i < 2400; i++) {
        final err = 1.0 - sim.hingeAngle(joint);
        sim.updateJoint(
          joint,
          hingeDesc(parent, child, motorTargetVelocity: (8 * err).clamp(-2, 2)),
        );
        sim.step(sim.fixedTimestep);
      }
      expect(sim.hingeAngle(joint), closeTo(1.0, 0.05));
      sim.dispose();
    });

    test('un tope EN π es inerte: por eso los topes van estrictamente dentro',
        () {
      // ODE compara el ángulo contra el tope, y el ángulo vuelve acotado a
      // (−π, π]. Un `hi` exactamente en π nunca se alcanza, y si el hinge se
      // pasa, el ángulo envuelve a ~−π y lo estampa el tope INFERIOR: la junta
      // salta al otro extremo. Por eso el descriptor del servo usa 3.10, no π,
      // y por eso el 100 % del slider aparca en 171.9°.
      final sim = OdeSimulation();
      final (:parent, :child, :joint) =
          buildHinge(sim, lower: -0.15, upper: 3.10, targetAngle: 3.10);

      for (var i = 0; i < 4800; i++) {
        sim.updateJoint(
          joint,
          hingeDesc(parent, child,
              lower: -0.15, upper: 3.10, motorTargetVelocity: 2.0),
        );
        sim.step(sim.fixedTimestep);
      }

      final angle = sim.hingeAngle(joint);
      printOnFailure('ángulo final: $angle');
      expect(angle, greaterThan(2.9),
          reason: 'tiene que llegar cerca del tope superior');
      expect(angle, lessThanOrEqualTo(3.15),
          reason: 'y NO envolver al extremo negativo');
      sim.dispose();
    });
  });

  test('EL IMPORTANTE: el ancla del hinge no se corre con los cuerpos rotados',
      () {
    // Ésta es la configuración exacta donde `Quaternion.rotate` traicionó al
    // spike: un cuerpo boca abajo (π) sobre un conjunto ladeado (30°). Con la
    // rotación inversa, el pivote se desplazaba hasta 2·|ancla|·sin(θ) y «el
    // horn se despegaba del case» — pero el solver no se quejaba, porque
    // mantenía sus dos anclas juntas alrededor del pivote equivocado.
    //
    // Por eso el test NO compara la implementación consigo misma: calcula el
    // punto esperado con Matrix4.compose (la convención con la que el renderer
    // PINTA) y lo contrasta con el ancla que ODE recibió de verdad. Si alguien
    // vuelve a meter la rotación inversa, esto se pone rojo sin necesidad de
    // teléfono.
    final sim = OdeSimulation();

    final rotA = Quaternion.axisAngle(Vector3(0, 0, 1), 0.52); // el tilt de 30°
    final rotB = rotA * Quaternion.axisAngle(Vector3(0, 0, 1), pi); // boca abajo
    final posA = Vector3(0.4, 7.0, -0.3);

    // Anclas NO triviales: con (0,0,0) el bug sería invisible.
    final anchorA = Vector3(-0.41, 1.27, 0.02);
    final anchorB = Vector3(-0.01, -0.39, -0.01);

    // El segundo cuerpo se coloca para que SU ancla caiga sobre la del
    // primero, que es lo que hace el ensamblador de verdad al montar una
    // pieza. (Si se colocan a ojo, el gap no es cero de salida y el test
    // estaría midiendo el descuido del montaje, no el backend.)
    final anchorWorld =
        Matrix4.compose(posA, rotA, Vector3.all(1)).transform3(anchorA.clone());
    final posB = anchorWorld -
        Matrix4.compose(Vector3.zero(), rotB, Vector3.all(1))
            .transform3(anchorB.clone());

    final a = sim.createBody(
      target: SimplePoseTarget(translation: posA, rotation: rotA),
      type: BodyType.dynamic_,
      additionalMass: 7.0,
    );
    sim.createColliders(a, BoxShape(halfExtents: Vector3(1.5, 1.25, 0.66)));
    final b = sim.createBody(
      target: SimplePoseTarget(translation: posB, rotation: rotB),
      type: BodyType.dynamic_,
      additionalMass: 2.0,
    );
    sim.createColliders(b, BoxShape(halfExtents: Vector3(1.9, 0.39, 0.53)));
    // Del mismo mecanismo: sin esto se rozan y el contacto interno fabrica
    // energía (el «algo lo impulsa hacia arriba» del spike).
    sim.setBodyCollisionGroup(a, 1);
    sim.setBodyCollisionGroup(b, 1);

    final joint = sim.createJoint(RevoluteJointDesc(
      bodyA: a,
      bodyB: b,
      localAxisA: Vector3(0, -1, 0),
      localAxisB: Vector3(0, -1, 0),
      localAnchorA: anchorA,
      localAnchorB: anchorB,
    ));

    // El punto esperado, por la convención de Matrix4.compose (la del render).
    final expected = anchorWorld;

    final got = sim.debugHingeAnchor(joint);
    printOnFailure('esperado: $expected   ODE tiene: $got');
    expect((got - expected).length, lessThan(1e-3),
        reason: 'el ancla que recibió ODE tiene que ser la que se pidió. Si se '
            'ha corrido, alguien está usando Quaternion.rotate (que aplica la '
            'rotación INVERSA) para pasar de local a mundo');

    // Y que la junta se mantenga: gap del solver ~0 tras dejar caer.
    addGround(sim);
    final lines = <String>[];
    sim.telemetry = lines.add;
    settle(sim, seconds: 4);

    expect(lines, isNotEmpty, reason: 'la telemetría tiene que emitir');
    final last = lines.last;
    printOnFailure(last);
    final gaps = RegExp(r'gap=([0-9.]+)/([0-9.]+)').firstMatch(last);
    expect(gaps, isNotNull, reason: 'la línea debe traer el gap del hinge');
    expect(double.parse(gaps!.group(1)!), lessThan(0.05),
        reason: 'gap A (lo que se PIDIÓ, visto desde cada cuerpo)');
    expect(double.parse(gaps.group(2)!), lessThan(0.05),
        reason: 'gap B (las anclas que ODE mantiene: violación del solver)');

    sim.dispose();
  });

  test('el signo del hinge NO depende de que el otro cuerpo sea el mundo', () {
    // Medido: ODE invierte el ángulo (y con él el sentido del motor) cuando el
    // primer cuerpo atado es el mundo. El contrato dice que el ángulo positivo
    // es B respecto a A, y eso no puede cambiar porque A resulte ser el suelo:
    // quien ancle una pieza al mundo se encontraría el motor al revés sin
    // ningún aviso. El backend lo normaliza; esto lo vigila.
    double angleAfterHalfSecond({required bool parentFixed}) {
      final sim = OdeSimulation();
      final parent = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: parentFixed ? BodyType.fixed : BodyType.dynamic_,
        additionalMass: parentFixed ? null : 5000.0, // hace de ancla
      );
      if (!parentFixed) {
        sim.createColliders(parent, BoxShape(halfExtents: Vector3(1, 1, 1)));
        sim.setBodyGravityScale(parent, 0);
        sim.setBodyCollisionGroup(parent, 1);
      }
      final child = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: BodyType.dynamic_,
        additionalMass: 2.0,
      );
      sim.createColliders(child, BoxShape(halfExtents: Vector3(1.9, .39, .53)));
      sim.setBodyGravityScale(child, 0);
      sim.setBodyCollisionGroup(child, 1);

      final joint = sim.createJoint(
        hingeDesc(parent, child, motorTargetVelocity: 2.0),
      );
      settle(sim, seconds: 0.5);
      final a = sim.hingeAngle(joint);
      sim.dispose();
      return a;
    }

    final anchoredToWorld = angleAfterHalfSecond(parentFixed: true);
    final betweenBodies = angleAfterHalfSecond(parentFixed: false);
    printOnFailure('al mundo: $anchoredToWorld   entre cuerpos: $betweenBodies');

    expect(betweenBodies, greaterThan(0.5),
        reason: 'velocidad objetivo positiva -> ángulo creciente');
    expect(anchoredToWorld, greaterThan(0.5),
        reason: 'y lo mismo anclado al mundo. Si sale negativo, el orden de '
            'dJointAttach volvió a invertir la convención');
  });

  test('el grupo de mecanismo apaga los contactos internos', () {
    // El «algo lo impulsa hacia arriba» del spike: dos piezas del mismo
    // conjunto a dos saltos de junta SÍ generan contactos, y con holguras
    // pequeñas arman un oscilador que fabrica energía. Un mecano atornillado
    // no se auto-colisiona.
    final sim = OdeSimulation();
    addGround(sim);

    // Dos cajas solapadas: sin grupo se empujan; con grupo se ignoran.
    int makeBox(double y) {
      final h = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, y, 0)),
        type: BodyType.dynamic_,
        additionalMass: 5.0,
      );
      sim.createColliders(h, BoxShape(halfExtents: Vector3(1, 1, 1)));
      return h;
    }

    final one = makeBox(4.0);
    final two = makeBox(4.6); // solapadas a propósito
    sim.setBodyCollisionGroup(one, 1);
    sim.setBodyCollisionGroup(two, 1);

    settle(sim, seconds: 3);
    final yOne = sim.readBodyPose(one).$1.y;
    final yTwo = sim.readBodyPose(two).$1.y;
    printOnFailure('y: $yOne / $yTwo');
    // Si se auto-colisionaran, la de arriba habría salido despedida.
    expect((yTwo - yOne).abs(), lessThan(0.9),
        reason: 'las dos del mismo grupo se atraviesan sin empujarse');
    sim.dispose();
  });

  test('los triggers dan un error que NO culpa a la forma', () {
    final sim = OdeSimulation();
    final body = sim.createBody(
      target: SimplePoseTarget(),
      type: BodyType.dynamic_,
      additionalMass: 1.0,
    );
    expect(
      () => sim.createColliders(
        body,
        BoxShape(halfExtents: Vector3.all(1)),
        isTrigger: true,
      ),
      throwsA(isA<UnsupportedError>()
          .having((e) => e.message, 'message', contains('isTrigger'))),
    );
    sim.dispose();
  });
}

({int parent, int child, int joint}) buildHinge(
  OdeSimulation sim, {
  double? lower,
  double? upper,
  double targetAngle = 1.0,
}) {
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
  sim.setBodyGravityScale(child, 0); // sin peso: se prueba el motor, no la caída
  final joint = sim.createJoint(
    hingeDesc(parent, child, lower: lower, upper: upper),
  );
  return (parent: parent, child: child, joint: joint);
}

RevoluteJointDesc hingeDesc(
  int a,
  int b, {
  double? lower,
  double? upper,
  double motorTargetVelocity = 0,
}) =>
    RevoluteJointDesc(
      bodyA: a,
      bodyB: b,
      localAxisA: Vector3(0, 0, 1),
      localAxisB: Vector3(0, 0, 1),
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3.zero(),
      lowerLimit: lower,
      upperLimit: upper,
      motorTargetVelocity: motorTargetVelocity,
      motorMaxForce: 1766.0,
    );

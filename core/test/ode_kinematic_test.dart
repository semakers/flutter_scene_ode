// LAS PIEZAS FIJAS del mecano: un cuerpo CINEMÁTICO.
//
// El niño puede marcar una pieza como fija para hacer un panel de botones
// clavado en el aire o una pared con la que un carrito choca. En el mecano eso
// se traduce en un único cambio: el cuerpo pasa a `BodyType.kinematic` al dar
// a Play y vuelve a `dynamic_` al parar.
//
// Los tres candidatos y por qué gana éste:
//
//  - `fixed` es el tipo del suelo y las paredes del escenario, pero para una
//    PIEZA no vale: ODE no le da `dBodyID`, así que `setBodyPose`, `wakeBody`
//    y las velocidades LANZAN — y son justo lo que el rig usa para mover,
//    escalar y volver a la pose de borrador. Además `setBodyKind` lo prohíbe
//    en vivo, y sin `dBodyID` el filtro de grupos de `_near` no se aplica: una
//    pieza fija chocaría con las de su propio mecanismo soldado.
//  - Anclar con un FixedJoint contra el mundo deja el cuerpo dinámico, así que
//    el ancla CEDE bajo carga (ERP/CFM) y puede resonar.
//  - `kinematic` conserva el `dBodyID`, no lo mueve nada, y se alterna en
//    vivo. Es lo que se prueba aquí.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_kinematic_test.dart
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

/// Una caja con cuerpo del tipo que se pida, puesta en [at] y quieta.
int box(
  OdeSimulation sim, {
  required BodyType type,
  required Vector3 at,
  Vector3? half,
  double mass = 20,
}) {
  final body = sim.createBody(
    target: SimplePoseTarget(translation: at),
    type: type,
    additionalMass: mass,
  );
  sim.createColliders(
    body,
    BoxShape(halfExtents: half ?? Vector3(2, 0.3, 2)),
    material: PhysicsMaterial(friction: 0.8),
  );
  return body;
}

double yOf(OdeSimulation sim, int body) => sim.readBodyPose(body).$1.y;

void main() {
  setUpAll(exigirOde);

  group('una pieza fija se queda donde la pusieron', () {
    test('en el AIRE, sin suelo debajo y con la gravedad puesta', () {
      // Es el caso entero: el panel de botones flotando. Un dinámico en la
      // misma posición cae; el cinemático no se mueve un micrómetro.
      final sim = OdeSimulation();
      addGround(sim);
      final fija = box(sim, type: BodyType.kinematic, at: Vector3(0, 8, 0));
      final suelta = box(sim, type: BodyType.dynamic_, at: Vector3(10, 8, 0));

      settle(sim, seconds: 3);

      expect(yOf(sim, fija), 8.0, reason: 'la fija no puede haberse movido');
      expect(yOf(sim, suelta), lessThan(1), reason: 'la suelta tiene que caer');
      sim.dispose();
    });

    test('y NO la empuja lo que le cae encima', () {
      // La otra mitad de la promesa: la pared aguanta. 20 g de caja soltada
      // desde 4 unidades por encima no la mueven.
      final sim = OdeSimulation();
      addGround(sim);
      final pared = box(sim, type: BodyType.kinematic, at: Vector3(0, 3, 0));
      final antes = sim.readBodyPose(pared).$1.clone();
      box(sim, type: BodyType.dynamic_, at: Vector3(0, 7, 0));

      settle(sim, seconds: 4);

      final despues = sim.readBodyPose(pared).$1;
      expect((despues - antes).length, closeTo(0, 1e-9));
      sim.dispose();
    });
  });

  group('pero SIGUE chocando: es una pieza, no un fantasma', () {
    test('lo que cae encima se queda encima, no la atraviesa', () {
      // Sin esto la propiedad no serviría para nada: una pared que no para a
      // nadie es una pared que no existe. La caja de arriba tiene que quedarse
      // a la altura de la chapa (0.3 + 0.3 de semialturas sobre y=3).
      final sim = OdeSimulation();
      addGround(sim);
      box(sim, type: BodyType.kinematic, at: Vector3(0, 3, 0));
      final encima = box(sim, type: BodyType.dynamic_, at: Vector3(0, 7, 0));

      settle(sim, seconds: 5);

      expect(yOf(sim, encima), closeTo(3.6, 0.05));
      sim.dispose();
    });

    test('sigue parando DESPUÉS de estar quieta un buen rato', () {
      // El autodisable del backend duerme a los cuerpos quietos con umbral
      // 0.08, y un cinemático está quieto POR DEFINICIÓN. Si dormirse le
      // quitara los contactos, la pared dejaría de existir al rato — un fallo
      // que sólo aparecería con el niño mirando.
      final sim = OdeSimulation();
      addGround(sim);
      box(sim, type: BodyType.kinematic, at: Vector3(0, 3, 0));
      settle(sim, seconds: 10);

      final tarde = box(sim, type: BodyType.dynamic_, at: Vector3(0, 7, 0));
      settle(sim, seconds: 5);

      expect(yOf(sim, tarde), closeTo(3.6, 0.05));
      sim.dispose();
    });
  });

  group('el interruptor: se alterna EN VIVO', () {
    test('dinámico → cinemático → dinámico, y al volver cae', () {
      // Es lo que permite que la marca se aplique en Start y se deshaga en
      // Stop, sin reconstruir la pieza. Con `fixed` esto lanzaría.
      final sim = OdeSimulation();
      addGround(sim);
      final pieza = box(sim, type: BodyType.dynamic_, at: Vector3(0, 8, 0));

      sim.setBodyKind(pieza, BodyType.kinematic);
      settle(sim, seconds: 3);
      expect(yOf(sim, pieza), 8.0, reason: 'fija: no se mueve');

      sim.setBodyKind(pieza, BodyType.dynamic_);
      sim.wakeBody(pieza);
      settle(sim, seconds: 3);
      expect(yOf(sim, pieza), lessThan(1), reason: 'suelta otra vez: cae');
      sim.dispose();
    });

    test('a `fixed` NO se cambia, y lo dice', () {
      // La razón de que el mecano use `kinematic`. Que esto lance es lo que
      // impide que alguien "arregle" el tipo un día y descubra el problema en
      // el teléfono.
      final sim = OdeSimulation();
      final pieza = box(sim, type: BodyType.dynamic_, at: Vector3(0, 8, 0));
      expect(
        () => sim.setBodyKind(pieza, BodyType.fixed),
        throwsUnsupportedError,
      );
      sim.dispose();
    });
  });

  group('lo que el rig sigue pudiendo hacerle', () {
    test('un cinemático conserva su dBodyID: nada del editor lanza', () {
      // `fixed` haría lanzar a los cinco. Esta es la prueba de que el editor
      // no necesita ni una rama nueva.
      final sim = OdeSimulation();
      final pieza = box(sim, type: BodyType.kinematic, at: Vector3(0, 5, 0));

      expect(() => sim.wakeBody(pieza), returnsNormally);
      expect(() => sim.setBodyLinearVelocity(pieza, Vector3.zero()),
          returnsNormally);
      expect(() => sim.setBodyAngularVelocity(pieza, Vector3.zero()),
          returnsNormally);
      expect(
        () => sim.setBodyPose(pieza, Vector3(1, 2, 3), Quaternion.identity()),
        returnsNormally,
      );
      expect(sim.readBodyPose(pieza).$1.y, 2.0);
      sim.dispose();
    });
  });
}

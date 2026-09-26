// El COMPUESTO: un cuerpo hecho de varias formas.
//
// Nace con los soportes del mecano, que el niño dibuja en una matriz 3×3: una
// placa en L tiene que chocar como una L, o las piezas se quedarían apoyadas
// sobre el hueco vacío. Antes de esto, `CompoundShape` caía en el `default:`
// de createColliders y `_applyBodyMass` re-escribía la masa entera por cada
// collider — dos colliders en un cuerpo se PISABAN, y el último se llevaba la
// inercia.
//
// Lo que estos tests protegen, en orden de importancia:
//
//  1. que un compuesto de UNA caja siga dando exactamente lo que daba
//     `dMassSetBoxTotal` (si no, los veinte goldens del arnés del mecano
//     dejarían de valer sin que nadie tocara el mecano);
//  2. que dos mitades pegadas pesen y giren como la caja entera — que es toda
//     la prueba de que la acumulación con Steiner está bien;
//  3. que el HUECO de una L sea hueco de verdad;
//  4. que un compuesto descentrado LANCE en vez de pivotar torcido en
//     silencio.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_compound_test.dart
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

/// Un cuerpo dinámico con la forma que se le pase, soltado desde [y].
int drop(
  OdeSimulation sim,
  Shape shape, {
  double y = 5,
  double? mass,
  Matrix4? localPose,
}) {
  final body = sim.createBody(
    target: SimplePoseTarget(translation: Vector3(0, y, 0)),
    type: BodyType.dynamic_,
    additionalMass: mass,
  );
  sim.createColliders(body, shape, localPose: localPose);
  return body;
}

CompoundChild child(Vector3 half, Vector3 at) => CompoundChild(
      shape: BoxShape(halfExtents: half),
      localPose: Matrix4.translation(at),
    );

void main() {
  setUpAll(skipIfNoOde);

  group('la masa', () {
    test('un compuesto de UNA caja da lo mismo que la caja suelta', () {
      // La compuerta de la compatibilidad: si esto se mueve, se mueven los
      // goldens del mecano sin que nadie haya tocado el mecano.
      final half = Vector3(2, 0.5, 3);

      final suelta = OdeSimulation();
      final a = drop(suelta, BoxShape(halfExtents: half), mass: 12);

      final compuesta = OdeSimulation();
      final b = drop(
        compuesta,
        CompoundShape(children: [child(half, Vector3.zero())]),
        mass: 12,
      );

      expect(compuesta.bodyMass(b), closeTo(suelta.bodyMass(a), 1e-9));
      final ia = suelta.bodyPrincipalInertia(a);
      final ib = compuesta.bodyPrincipalInertia(b);
      printOnFailure('suelta $ia  compuesta $ib');
      expect(ib.x, closeTo(ia.x, 1e-9));
      expect(ib.y, closeTo(ia.y, 1e-9));
      expect(ib.z, closeTo(ia.z, 1e-9));

      suelta.dispose();
      compuesta.dispose();
    });

    test('DOS mitades pegadas pesan y giran como la caja entera', () {
      // Es la prueba de Steiner: cada mitad aporta su tensor propio MÁS el
      // término del brazo. Sin él, la inercia sale corta y el conjunto gira
      // más rápido de lo que debe, sin ningún error.
      final entera = OdeSimulation();
      final a = drop(entera, BoxShape(halfExtents: Vector3(2, 0.5, 3)),
          mass: 12);

      final partida = OdeSimulation();
      final b = drop(
        partida,
        CompoundShape(children: [
          child(Vector3(1, 0.5, 3), Vector3(-1, 0, 0)),
          child(Vector3(1, 0.5, 3), Vector3(1, 0, 0)),
        ]),
        mass: 12,
      );

      expect(partida.bodyMass(b), closeTo(entera.bodyMass(a), 1e-9));
      final ia = entera.bodyPrincipalInertia(a);
      final ib = partida.bodyPrincipalInertia(b);
      printOnFailure('entera $ia  partida $ib');
      expect(ib.x, closeTo(ia.x, 1e-9));
      expect(ib.y, closeTo(ia.y, 1e-9));
      expect(ib.z, closeTo(ia.z, 1e-9));

      entera.dispose();
      partida.dispose();
    });

    test('sin `mass` la densidad se aplica a CADA caja, no a la primera', () {
      final sim = OdeSimulation();
      final body = drop(
        sim,
        CompoundShape(children: [
          child(Vector3(1, 1, 1), Vector3(-1, 0, 0)),
          child(Vector3(1, 1, 1), Vector3(1, 0, 0)),
        ]),
      );
      // Dos cajas de 2×2×2 = 16 unidades de volumen por la densidad por
      // defecto del contrato.
      final densidad = PhysicsMaterial.defaultMaterial.density;
      expect(sim.bodyMass(body), closeTo(16 * densidad, 1e-9));
      sim.dispose();
    });
  });

  group('el hueco es hueco', () {
    // LA L DE LA FOTO, con los números hechos a mano (este paquete no conoce
    // el mecano, así que aquí no hay `SupportShape` que preguntar):
    //
    //   celdas (fila,col): (0,0) (1,0) (2,0) (2,1) (2,2), paso 1.5
    //   centro de la celda en el frame de la matriz: ((col−1)·1.5, (fila−1)·1.5)
    //   centroide de las cinco: (−0.6, +0.6)
    //
    // Dos rectángulos: la columna (1×3) y la fila que sobra (2×1), YA
    // referidos al centroide — que es donde tiene que estar el origen del
    // cuerpo, porque ODE integra alrededor de él.
    //
    //   columna  centro (−0.9, 0, −0.6)   semiejes (0.75, 0.15, 2.25)
    //   fila     centro (+1.35, 0, +0.9)  semiejes (1.50, 0.15, 0.75)
    //
    // Comprobación de que el origen ES el centro de masa (3 celdas y 2):
    //   x: (3·(−0.9) + 2·(+1.35))/5 = 0      z: (3·(−0.6) + 2·(+0.9))/5 = 0
    CompoundShape ele() => CompoundShape(children: [
          child(Vector3(0.75, 0.15, 2.25), Vector3(-0.9, 0, -0.6)),
          child(Vector3(1.50, 0.15, 0.75), Vector3(1.35, 0, 0.9)),
        ]);

    /// Una celda cualquiera, en el frame del CUERPO (o sea, ya sin centroide).
    Vector3 celda(int fila, int col) =>
        Vector3((col - 1) * 1.5 + 0.6, 0, (fila - 1) * 1.5 - 0.6);

    int placa(OdeSimulation sim) {
      final body = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 3, 0)),
        type: BodyType.dynamic_,
        additionalMass: 9.1125, // 5 celdas de 1.8225 g
      );
      sim.createColliders(body, ele());
      return body;
    }

    int testigoSobre(OdeSimulation sim, Vector3 donde) {
      final body = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(donde.x, 3.8, donde.z)),
        type: BodyType.dynamic_,
        additionalMass: 2,
      );
      sim.createColliders(body, BoxShape(halfExtents: Vector3.all(0.4)));
      return body;
    }

    test('el HUECO de la L no sostiene nada: el testigo llega al suelo', () {
      final sim = OdeSimulation();
      addGround(sim);
      final soporte = placa(sim);
      // (0,2) es la esquina que la L NO tiene.
      final testigo = testigoSobre(sim, celda(0, 2));
      settle(sim, seconds: 8);

      final (posPlaca, _) = sim.readBodyPose(soporte);
      final (posTestigo, _) = sim.readBodyPose(testigo);
      printOnFailure('placa $posPlaca   testigo $posTestigo');

      expect(
        posPlaca.y,
        closeTo(0.15, 0.05),
        reason: 'la placa apoya de plano: su centro queda a media chapa',
      );
      expect(
        posTestigo.y,
        closeTo(0.4, 0.08),
        reason: 'el testigo tiene que llegar al SUELO (0.4 = su semilado). Si '
            'se queda a ~0.7 está apoyado sobre el hueco: el compuesto está '
            'chocando como su caja envolvente',
      );
      sim.dispose();
    });

    test('sobre la PLACA sí se apoya — la contraprueba del mismo montaje', () {
      final sim = OdeSimulation();
      addGround(sim);
      placa(sim);
      // (1,0) sí es placa: está en la columna de la L.
      final testigo = testigoSobre(sim, celda(1, 0));
      settle(sim, seconds: 8);

      final (posTestigo, _) = sim.readBodyPose(testigo);
      printOnFailure('testigo $posTestigo');
      expect(
        posTestigo.y,
        closeTo(0.7, 0.08),
        reason: 'encima de la chapa: 0.3 de placa + 0.4 de semilado',
      );
      sim.dispose();
    });

    test('la inercia de la L NO es la de su caja envolvente', () {
      // Sin esto, una implementación que usara el AABB pasaría los dos tests
      // de arriba en cuanto el testigo cayera por los pelos.
      final laL = OdeSimulation();
      final a = laL.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: BodyType.dynamic_,
        additionalMass: 9.1125,
      );
      laL.createColliders(a, ele());

      final cuadrada = OdeSimulation();
      final b = cuadrada.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: BodyType.dynamic_,
        additionalMass: 9.1125,
      );
      cuadrada.createColliders(
          b, BoxShape(halfExtents: Vector3(2.25, 0.15, 2.25)));

      final iL = laL.bodyPrincipalInertia(a);
      final iCaja = cuadrada.bodyPrincipalInertia(b);
      printOnFailure('L $iL   envolvente $iCaja');
      expect(
        (iL.y - iCaja.y).abs(),
        greaterThan(1.0),
        reason: 'la L reparte su masa distinto que el cuadrado; si coinciden, '
            'la acumulación está usando la envolvente',
      );

      laL.dispose();
      cuadrada.dispose();
    });
  });

  group('las guardas', () {
    test('un compuesto DESCENTRADO lanza, en vez de pivotar torcido', () {
      final sim = OdeSimulation();
      expect(
        () => drop(
          sim,
          CompoundShape(children: [
            child(Vector3(1, 1, 1), Vector3(0, 0, 0)),
            child(Vector3(1, 1, 1), Vector3(4, 0, 0)),
          ]),
          mass: 10,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('centro de masa'),
        )),
      );
      sim.dispose();
    });

    test('los compuestos ANIDADOS no', () {
      final sim = OdeSimulation();
      expect(
        () => drop(
          sim,
          CompoundShape(children: [
            CompoundChild(
              shape: CompoundShape(children: [child(Vector3.all(1), Vector3.zero())]),
              localPose: Matrix4.identity(),
            ),
          ]),
        ),
        throwsUnsupportedError,
      );
      sim.dispose();
    });

    test('un compuesto SIN hijos lo dice', () {
      final sim = OdeSimulation();
      expect(
        () => drop(sim, CompoundShape(children: const [])),
        throwsUnsupportedError,
      );
      sim.dispose();
    });
  });

  group('el ciclo de vida', () {
    test('createColliders devuelve UN handle por hijo', () {
      final sim = OdeSimulation();
      final body = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: BodyType.dynamic_,
        additionalMass: 6,
      );
      final handles = sim.createColliders(
        body,
        CompoundShape(children: [
          child(Vector3(1, 1, 1), Vector3(-1, 0, 0)),
          child(Vector3(1, 1, 1), Vector3(1, 0, 0)),
        ]),
      );
      expect(handles, hasLength(2));
      expect(handles.toSet(), hasLength(2), reason: 'y no repetidos');

      // Destruirlos todos no deja geoms vivos: el siguiente step no revienta.
      for (final h in handles) {
        sim.destroyCollider(h);
      }
      settle(sim, seconds: 0.5);
      sim.dispose();
    });

    test('setBodyAdditionalMass re-reparte entre TODOS los hijos', () {
      final sim = OdeSimulation();
      final body = sim.createBody(
        target: SimplePoseTarget(translation: Vector3(0, 5, 0)),
        type: BodyType.dynamic_,
        additionalMass: 6,
      );
      sim.createColliders(
        body,
        CompoundShape(children: [
          child(Vector3(1, 1, 1), Vector3(-1, 0, 0)),
          child(Vector3(1, 1, 1), Vector3(1, 0, 0)),
        ]),
      );
      expect(sim.bodyMass(body), closeTo(6, 1e-9));

      sim.setBodyAdditionalMass(body, 30);
      expect(
        sim.bodyMass(body),
        closeTo(30, 1e-9),
        reason: 'mirar solo el primer collider dejaría el cuerpo en 15',
      );
      sim.dispose();
    });
  });
}

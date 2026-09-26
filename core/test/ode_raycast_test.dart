// El raycast nativo del backend. Su cliente real es el sensor que mide de
// verdad (el ultrasónico del mecano); el pick de piezas del editor va por el
// raycast de MALLA de flutter_scene, no por aquí.
//
// Dos rarezas de ODE que estos tests respetan a propósito:
//  - ray↔cylinder: la guarda es `tt > 0` ESTRICTA (ray.cpp), así que un rayo
//    lanzado desde la superficie exacta del cilindro NO impacta (caja, esfera
//    y plano sí aceptan distancia 0). Ningún rayo sale de una superficie.
//  - `distance` va en unidades de MUNDO sobre la dirección normalizada
//    (dGeomRaySet normaliza él mismo), no en el parámetro `t` de `Ray.at(t)`.
//
// Correr con:
//   ODE_LIBRARY_PATH=<...>/libode.so dart test test/ode_raycast_test.dart
import 'package:test/test.dart';
import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

import 'ode_test_util.dart';

// Las medidas de la llanta del motor DC, tomadas del GLB (las mismas del
// banco del cilindro).
const kRadius = 1.5894;
const kHalfHeight = 0.6362;

Ray rayDown(double x, double y, double z) =>
    Ray.originDirection(Vector3(x, y, z), Vector3(0, -1, 0));

/// Caja dinámica de 1×1×1 (semiextensión 0.5) con el centro en [center].
(int body, int collider) addBox(OdeSimulation sim, Vector3 center) {
  final body = sim.createBody(
    target: SimplePoseTarget(translation: center),
    type: BodyType.dynamic_,
  );
  final colliders = sim.createColliders(
    body,
    BoxShape(halfExtents: Vector3.all(0.5)),
  );
  return (body, colliders.single);
}

void main() {
  setUpAll(skipIfNoOde);

  test('caja fixed: distancia, punto y normal del suelo', () {
    final sim = OdeSimulation();
    addGround(sim);
    // La cara superior del suelo está en y = 0 (ver addGround).
    final hit = sim.raycast(rayDown(0, 5, 0));
    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(5.0, 1e-3));
    expect(hit.worldPoint.x, closeTo(0, 1e-3));
    expect(hit.worldPoint.y, closeTo(0, 1e-3));
    expect(hit.worldPoint.z, closeTo(0, 1e-3));
    // La convención de la normal del backend: mira HACIA el origen del rayo.
    expect(hit.worldNormal.y, closeTo(1.0, 1e-3),
        reason: 'rayo hacia abajo contra la cara superior → normal +Y');
    sim.dispose();
  });

  test('cilindro tumbado: la pareja ray↔cylinder nativa', () {
    final sim = OdeSimulation();
    // La llanta tumbada (eje del shape Y → Z del cuerpo), centro a y=kRadius:
    // descansa sobre su radio, la cima queda en y = 2·kRadius.
    final body = sim.createBody(
      target: SimplePoseTarget(translation: Vector3(0, kRadius, 0)),
      type: BodyType.dynamic_,
    );
    sim.createColliders(
      body,
      const CylinderShape(radius: kRadius, halfHeight: kHalfHeight),
      localPose: wheelLocalPose(),
    );
    final hit = sim.raycast(rayDown(0, 5, 0));
    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(5.0 - 2 * kRadius, 1e-3));
    expect(hit.worldPoint.y, closeTo(2 * kRadius, 1e-3));
    expect(hit.worldNormal.y, closeTo(1.0, 1e-3));
    sim.dispose();
  });

  test('raycastAll: orden ascendente por distancia', () {
    final sim = OdeSimulation();
    final groundBody = addGround(sim);
    final (_, boxCollider) = addBox(sim, Vector3(0, 3, 0));
    final hits = sim.raycastAll(rayDown(0, 10, 0));
    expect(hits, hasLength(2));
    expect(hits[0].colliderHandle, boxCollider);
    expect(hits[0].distance, closeTo(10 - 3.5, 1e-3));
    expect(hits[1].distance, closeTo(10.0, 1e-3));
    expect(hits[0].distance, lessThan(hits[1].distance));
    // El del suelo es el collider del cuerpo fixed.
    expect(sim.raycast(rayDown(3, 10, 3))!.distance, closeTo(10.0, 1e-3),
        reason: 'lejos de la caja solo queda el suelo ($groundBody)');
    sim.dispose();
  });

  test('maxDistance corta', () {
    final sim = OdeSimulation();
    addGround(sim);
    expect(sim.raycast(rayDown(0, 5, 0), maxDistance: 4.0), isNull);
    expect(sim.raycastAll(rayDown(0, 5, 0), maxDistance: 4.0), isEmpty);
    expect(sim.raycast(rayDown(0, 5, 0), maxDistance: 6.0), isNotNull);
    sim.dispose();
  });

  test('includeFixed:false filtra el suelo y deja lo dinámico', () {
    final sim = OdeSimulation();
    addGround(sim);
    final (_, boxCollider) = addBox(sim, Vector3(0, 3, 0));
    expect(sim.raycast(rayDown(3, 10, 3), includeFixed: false), isNull);
    final hit = sim.raycast(rayDown(0, 10, 0), includeFixed: false);
    expect(hit, isNotNull);
    expect(hit!.colliderHandle, boxCollider);
    sim.dispose();
  });

  test('un cuerpo dormido sigue siendo impactado', () {
    final sim = OdeSimulation();
    addGround(sim);
    final (body, boxCollider) = addBox(sim, Vector3(0, 0.6, 0));
    settle(sim, seconds: 8);
    // isBodySleeping solo acepta cuerpos con dBody (lanza con fixed).
    expect(sim.isBodySleeping(body), isTrue,
        reason: 'la caja debe dormirse en el suelo antes de la aserción real');
    final hit = sim.raycast(rayDown(0, 5, 0), includeFixed: false);
    expect(hit, isNotNull,
        reason: 'dCollide no consulta el enable del cuerpo: dormido ≠ '
            'invisible al rayo');
    expect(hit!.colliderHandle, boxCollider);
    sim.dispose();
  });

  test('rayo al vacío', () {
    final sim = OdeSimulation();
    addGround(sim);
    final up = Ray.originDirection(Vector3(0, 5, 0), Vector3(0, 1, 0));
    expect(sim.raycast(up), isNull);
    expect(sim.raycastAll(up), isEmpty);
    sim.dispose();
  });

  test('la dirección sin normalizar da la MISMA distancia (unidades de mundo)',
      () {
    final sim = OdeSimulation();
    addGround(sim);
    final scaled =
        sim.raycast(Ray.originDirection(Vector3(0, 5, 0), Vector3(0, -7, 0)));
    expect(scaled, isNotNull);
    expect(scaled!.distance, closeTo(5.0, 1e-3),
        reason: 'dGeomRaySet normaliza: distance nunca es el t de Ray.at(t)');
    sim.dispose();
  });

  test('dirección cero: null y lista vacía, sin tocar la FFI', () {
    final sim = OdeSimulation();
    addGround(sim);
    // Sin la guardia, dNormalize3 en este build (dNODEBUG) deja (1,0,0) EN
    // SILENCIO y esto devolvería impactos reales hacia +X.
    final zero = Ray.originDirection(Vector3(0, 5, 0), Vector3.zero());
    expect(sim.raycast(zero), isNull);
    expect(sim.raycastAll(zero), isEmpty);
    sim.dispose();
  });

  test('layerMask sin el bit 1: vacío (no hay capas, todo es capa 1)', () {
    final sim = OdeSimulation();
    addGround(sim);
    expect(sim.raycast(rayDown(0, 5, 0), layerMask: 0x2), isNull);
    expect(sim.raycastAll(rayDown(0, 5, 0), layerMask: 0x2), isEmpty);
    expect(sim.raycast(rayDown(0, 5, 0), layerMask: 0x3), isNotNull);
    sim.dispose();
  });
}

/// El localPose de la llanta: manda el eje del shape (Y) al Z del cuerpo.
/// (Duplicado de ode_cylinder_test.dart, que lo tiene como helper privado de
/// archivo.)
Matrix4 wheelLocalPose() => Matrix4.compose(
      Vector3.zero(),
      Quaternion.axisAngle(Vector3(1, 0, 0), pi / 2),
      Vector3.all(1),
    );

// OdeSimulation: backend de ODE 0.16.6 tras el contrato `PhysicsSimulation`
// de package:scene (el que consumen los componentes
// PhysicsWorld/RigidBody/Collider/Joint de flutter_scene).
//
// Cubre: cuerpos dynamic/kinematic/fixed, colliders Box, Sphere y Cylinder,
// compuestos de ésos (CompoundShape, plano), juntas Revolute (hinge
// motorizado) y Fixed (soldadura), step con QuickStep y contactos por
// nearCallback (NativeCallable). Extras fuera del contrato (vía downcast):
// [hingeAngle], [hingeAngleRate], [paused] y [setBodyCollisionGroup].
//
// UNIDADES — no son las obvias, y equivocarlas es el fallo más caro que dio el
// spike. 1 unidad ≈ 1 cm, **masas en GRAMOS**, gravedad -9.81. Con masas en kg
// (0.002-0.009 para un servo) los multiplicadores del solver quedan al nivel
// del CFM: contactos y soldaduras se vuelven gelatina que RESUENA sin
// converger, y el conjunto se mece eternamente sin dormir jamás. En gramos las
// fuerzas quedan ~100 y el CFM 1e-5 vuelve a ser regularización despreciable.
// Consecuencia aceptada: la dinámica corre ~10x lenta ("cámara lenta x10").
//
// LÍMITES DE ESTE BACKEND. Cada uno con el síntoma que produce, para que quien
// se lo encuentre lo reconozca en vez de perseguirlo:
//
// - `additionalMass` se trata como masa TOTAL del cuerpo (el contrato dice
//   "adicional a la derivada de los colliders"). En un compuesto se reparte
//   entre sus hijos por volumen.
//   SÍNTOMA: dos `Collider` (COMPONENTES distintos) en un mismo Node siguen
//   pisándose la masa — [createColliders] acumula dentro de UNA llamada, no
//   entre llamadas. Se manifiesta como resonancia que no duerme, fácil de
//   confundir con un problema de unidades. Por eso el ensamblador del mecano
//   asserta un solo Collider por cuerpo, y una pieza de varias cajas se pide
//   con un `CompoundShape`, que sí acumula.
// - El centro de masa queda en el ORIGEN del cuerpo aunque el collider tenga
//   offset (ODE lo exige y aquí no se re-centra). En un COMPUESTO eso deja de
//   ser gratis, y por eso [_applyCompoundMass] lo comprueba y LANZA: quien
//   dibuja la forma sabe dónde cae su centroide y puede poner ahí el origen.
//   NO es una limitación si el consumidor pone el origen del cuerpo en el
//   centro de su proxy — que es lo que hace el ensamblador del mecano, y por
//   eso allí esto es exacto. SÍNTOMA si no se hace: el cuerpo pivota alrededor
//   de un punto que no es su centro; con el motor DC el COM caería por debajo
//   del suelo.
// - Sin eventos de colisión: el Stream de [collisions] NUNCA emite.
// - Queries: [raycast] y [raycastAll] están implementadas (rayo nativo de ODE
//   contra cada collider; el editor las usa para sensores tipo ultrasónico —
//   el pick de piezas del editor va por el raycast de MALLA de flutter_scene,
//   no por aquí). [overlapSphere], [overlapBox] y [shapeCast] siguen vacías.
//   `layerMask`: no hay capas — todo collider cuenta como capa 1.
// - `frictionCombine`: [_near] PROMEDIA, salvo que uno de los dos materiales
//   pida `CombineRule.min` (2026-09-20). El promedio se queda por defecto
//   porque la aritmética del motor DC del mecano está derivada CON él. El
//   `min` existe para lo que RUEDA sin modelarse rodando —la rueda loca—: con
//   el promedio, un μ de 0.06 contra un piso de 0.8 sale a 0.43, y el apoyo
//   que tenía que no estorbar frena casi tanto como traccionan las llantas.
//   `max` y `multiply` siguen sin cablear: nadie los pide.
// - [setColliderFilter] es un no-op; no hay capas ni máscaras. El caso real
//   (un mecano atornillado no se auto-colisiona) lo cubre
//   [setBodyCollisionGroup].
// - Sin cápsulas y sin cilindro-contra-cilindro: se compila sin libccd, así
//   que esas parejas no están registradas y `dCollide` devolvería 0 EN
//   SILENCIO. Ver NATIVE.md.
import 'dart:async';
import 'dart:math' as math;

import 'package:scene/physics.dart' as sim;
import 'package:vector_math/vector_math.dart';

import '../interpolation.dart';
import '../rotation.dart';
// `ffi` NO es `dart:ffi` aquí, y es lo ÚNICO que cambia en este archivo entre
// las seis plataformas: es la costura que lo sustituye por una ABI equivalente
// sobre el heap del módulo wasm cuando se compila para web. En nativo
// reexporta `dart:ffi` pelado, así que abajo no cambia absolutamente nada.
// Lo mismo con `ffi_alloc.dart`, que es `calloc`. Ver ffi_shim.dart.
import 'ffi_alloc.dart';
import 'ffi_shim.dart' as ffi;
import 'ode_bindings.dart';
import 'ode_library.dart';
import 'ode_telemetry.dart';

class _OdeBody {
  _OdeBody({
    required this.type,
    required this.target,
    this.additionalMass,
  });

  sim.BodyType type;
  final sim.PoseTarget? target;

  /// null para cuerpos fixed (geom estático) y para anchors de mundo.
  ffi.Pointer<dxBody>? body;
  double? additionalMass;

  /// Pose cacheada (la única, para fixed; prev/curr para interpolar, para
  /// dinámicos).
  final Vector3 prevPos = Vector3.zero();
  final Quaternion prevRot = Quaternion.identity();
  final Vector3 currPos = Vector3.zero();
  final Quaternion currRot = Quaternion.identity();

  final List<int> colliderHandles = [];
}

class _OdeCollider {
  _OdeCollider({
    required this.geom,
    required this.bodyHandle,
    required this.material,
    required this.shape,
    required this.localRot,
    required this.localOffset,
  });

  final ffi.Pointer<dxGeom> geom;
  final int bodyHandle;
  sim.PhysicsMaterial material;
  final sim.Shape shape;

  /// Rotación del `localPose`. Se guarda porque re-derivar la masa más tarde
  /// (setBodyAdditionalMass) necesita volver a rotar el tensor de inercia al
  /// frame del cuerpo.
  final Quaternion localRot;

  /// Traslación del `localPose`, en el frame del cuerpo. Sólo importa cuando
  /// el cuerpo lleva VARIOS colliders (un compuesto): ahí es el brazo del
  /// teorema de Steiner. Con uno solo vale cero y no se usa — el contrato pone
  /// el origen del cuerpo en el centro de su proxy.
  final Vector3 localOffset;
}

sealed class _OdeJoint {
  _OdeJoint(this.joint);
  final ffi.Pointer<dxJoint> joint;
}

class _OdeHinge extends _OdeJoint {
  _OdeHinge(
    super.joint,
    this.bodyA,
    this.bodyB,
    this.requestedAnchorA,
    this.requestedAnchorB,
  );

  final int bodyA;
  final int bodyB;

  /// El ancla que se PIDIÓ al crear la junta, en el frame de cada cuerpo.
  ///
  /// Ojo con el nombre: NO es el ancla que ODE mantiene (esa se lee con
  /// `dJointGetHingeAnchor`/`Anchor2`). La distinción no es cosmética — es
  /// justo la que hace útil la telemetría. Cuando `Quaternion.rotate` metió la
  /// rotación inversa, el solver mantenía sus dos anclas perfectamente juntas
  /// (gap del solver = 0) alrededor de un pivote CORRIDO, y solo comparar
  /// contra lo que se había pedido delataba el desplazamiento.
  ///
  /// Se guardan siempre, con telemetría o sin ella: son 24 bytes por junta y
  /// son la red que evita que esa lección se vuelva a perder.
  final Vector3 requestedAnchorA;
  final Vector3 requestedAnchorB;
}

class _OdeFixed extends _OdeJoint {
  _OdeFixed(super.joint);
}

class OdeSimulation extends sim.PhysicsSimulation {
  /// [telemetry] se puede dejar en null y encender después: el campo es
  /// mutable a propósito, porque la mitad de las veces uno quiere mirar
  /// cuando la escena ya está corriendo raro.
  OdeSimulation({
    this.telemetry,
    this.telemetryPeriod = 1.0,
  }) {
    final lib = openOdeLibrary();
    if (lib == null) {
      // Que el constructor lance está bien; lo que no puede fallar es
      // PREGUNTAR. Para eso están isAvailable/unavailableReason, que es lo
      // que hay que consultar antes de llegar aquí.
      throw StateError(odeUnavailableReason ?? 'libode no disponible');
    }
    _lib = lib;
    _ode = OdeBindings(_lib);
    _ode.dInitODE2(0);
    // Los bindings tienen dReal = ffi.Float clavado: un .so en doble precisión
    // no daría error de enlace, leería basura.
    assertOdeAbi(_ode);
    _world = _ode.dWorldCreate();
    _space = _ode.dHashSpaceCreate(ffi.nullptr);
    _contactGroup = _ode.dJointGroupCreate(0);

    // Tuning del mundo (plan F3): fixed + hinges motorizados piden más
    // iteraciones que el default 20 del QuickStep.
    // Con masas en GRAMOS (fuerzas ~100) el CFM 1e-5 vuelve a ser
    // regularización despreciable, como debe.
    _ode.dWorldSetCFM(_world, 1e-5);
    _ode.dWorldSetERP(_world, 0.2);
    _ode.dWorldSetQuickStepNumIterations(_world, 40);
    _ode.dWorldSetContactSurfaceLayer(_world, 0.001);
    // 1.0 (no 10): con 10, la corrección de penetración del impacto
    // EYECTABA el conjunto (case1 rebotaba de y=0.9 a 5.7).
    _ode.dWorldSetContactMaxCorrectingVel(_world, 1.0);
    _ode.dWorldSetAutoDisableFlag(_world, 1);
    // 0.08: con 0.05 un rodar lentísimo (~0.06 u/s) nunca dormía y el
    // conjunto tardaba una eternidad en pararse del todo.
    _ode.dWorldSetAutoDisableLinearThreshold(_world, 0.08);
    _ode.dWorldSetAutoDisableAngularThreshold(_world, 0.08);

    // 1/240 (el diseño decía 1/120): con masas de gramos + motores + weld,
    // a 1/120 el solver dejaba un ruido perpetuo (|v|≈1-3) que nunca
    // dormía al conjunto y lo mecía en el aire. A 1/240 converge.
    // maxSubsteps 16 para cubrir un frame de ~66 ms (15 fps) sin soltar
    // tiempo.
    fixedTimestep = 1.0 / 240.0;
    maxSubsteps = 16;

    _contactGeoms = calloc<dContactGeom>(_maxContacts);
    _contact = calloc<dContact>();
    _q = calloc<dReal>(4);
    _mass = calloc<dMass>();
    // dVector3 son 4 floats (el cuarto es padding en ODE).
    _v3a = calloc<dReal>(4);
    _v3b = calloc<dReal>(4);
    // dMatrix3 son 12 floats (3 filas de 4).
    _rot = calloc<dReal>(12);
    // Buffer propio del raycast: _contactGeoms es del _near y un raycast en
    // medio de un step (callback futuro) lo pisaría.
    _rayContact = calloc<dContactGeom>();

    _nearCallable = ffi.NativeCallable<
        ffi.Void Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<dxGeom>,
          ffi.Pointer<dxGeom>,
        )>.isolateLocal(_near);
  }

  /// Si hay backend nativo en esta plataforma. Seguro de llamar en todas
  /// partes: es lo que decide entre abrir el constructor y enseñar la pantalla
  /// «este dispositivo no puede abrir el constructor».
  static bool get isAvailable => openOdeLibrary() != null;

  /// Deja el backend listo para que [isAvailable] diga la verdad.
  ///
  /// En nativo no hay nada que esperar: abrir la librería es síncrono y esto
  /// devuelve un futuro ya completado. En web el módulo wasm hay que
  /// descargarlo e instanciarlo, y eso no cabe en un getter.
  ///
  /// **Nunca lanza**, igual que la carga: si algo falla, se cachea el motivo y
  /// [isAvailable] pasa a false. El camino triste no necesita código nuevo, es
  /// el mismo de siempre.
  static Future<void> ensureAvailable() => ensureOdeLibrary();

  /// Por qué no, para poder enseñárselo a alguien. null si sí está.
  static String? get unavailableReason => odeUnavailableReason;

  late final ffi.DynamicLibrary _lib;
  late final OdeBindings _ode;
  late final ffi.Pointer<dxWorld> _world;
  late final ffi.Pointer<dxSpace> _space;
  late final ffi.Pointer<dxJointGroup> _contactGroup;

  static const int _maxContacts = 8;
  late final ffi.Pointer<dContactGeom> _contactGeoms;
  late final ffi.Pointer<dContact> _contact;
  late final ffi.Pointer<dReal> _q;
  late final ffi.Pointer<dMass> _mass;
  late final ffi.Pointer<dReal> _v3a;
  late final ffi.Pointer<dReal> _v3b;
  late final ffi.Pointer<dReal> _rot;
  late final ffi.Pointer<dContactGeom> _rayContact;

  /// Ray geom cacheado, lazy (casi ninguna escena raycastea). Va con space
  /// NULO — legal en ODE (`dxGeom` solo hace dSpaceAdd si hay espacio) — así
  /// que JAMÁS participa en el dSpaceCollide del step. Se destruye en
  /// [dispose]; la restricción real es hacerlo antes de dCloseODE (no de
  /// dSpaceDestroy: el rayo no está en el espacio).
  ffi.Pointer<dxGeom>? _rayGeom;
  late final ffi.NativeCallable<
      ffi.Void Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<dxGeom>,
        ffi.Pointer<dxGeom>,
      )> _nearCallable;

  int _nextHandle = 1;
  final Map<int, _OdeBody> _bodies = {};
  final Map<int, _OdeCollider> _colliders = {};
  final Map<int, _OdeJoint> _joints = {};

  /// geom address -> collider handle (para material en el nearCallback).
  final Map<int, int> _geomToCollider = {};

  /// dBodyID.address -> grupo de mecanismo. Dos cuerpos del MISMO grupo
  /// (≠0) no generan contactos entre sí: un mecano atornillado no se
  /// auto-colisiona (horn de un servo vs case del OTRO están a 2 saltos de
  /// junta — dAreConnectedExcluding no los cubre — y con 0.11 de holgura
  /// en el draft el roce del impacto armaba un oscilador perpetuo).
  /// Extra fuera del contrato, vía downcast.
  final Map<int, int> _bodyGroup = {};

  /// dBodyID.address -> penetración MÁXIMA contra algo AJENO en el paso
  /// que se está resolviendo. Lo llena [_near] y lo VACÍA [step] al empezar.
  ///
  /// Vaciarlo al empezar y no al terminar es la diferencia entre que esto
  /// sirva o no: quien lo consulta lo hace ENTRE pasos, así que limpiarlo al
  /// final del paso le enseñaría siempre un mapa vacío.
  ///
  /// «Ajeno» quiere decir lo que ya decidía [_near] antes de llegar aquí: no
  /// cuentan los cuerpos unidos por una junta ni los del mismo
  /// [_bodyGroup] — o sea que el bumper de un mecano NO se dispara con su
  /// propio chasis. Sí cuenta el suelo y cualquier geom sin cuerpo.
  ///
  /// Indexado por DIRECCIÓN, como [_bodyGroup], pero aquí la reutilización de
  /// direcciones que mata allí es inofensiva: el contenido vive un solo paso.
  final Map<int, double> _touching = {};

  /// ¿Este cuerpo tocó algo ajeno durante el último [step]?
  ///
  /// Extra fuera del contrato, vía downcast — es lo que hace posible una
  /// entrada digital que se acciona al CHOCAR y no con el dedo.
  bool bodyTouching(int bodyHandle) {
    final b = _bodies[bodyHandle]?.body;
    return b != null && _touching.containsKey(b.address);
  }

  /// La penetración máxima de ese contacto, en unidades de mundo. 0 si no
  /// tocó nada. Un contacto rasante da un número muy pequeño pero
  /// [bodyTouching] ya dice `true`: no se derive uno del otro con un `> 0`.
  double bodyContactDepth(int bodyHandle) {
    final b = _bodies[bodyHandle]?.body;
    return b == null ? 0 : (_touching[b.address] ?? 0);
  }

  void setBodyCollisionGroup(int bodyHandle, int group) {
    final b = _body(bodyHandle).body;
    if (b != null) _bodyGroup[b.address] = group;
  }

  final _collisions = StreamController<sim.SimCollisionEvent>.broadcast();

  /// Con true, [step] no avanza (la escena queda congelada donde está).
  bool paused = false;

  bool _disposed = false;

  @override
  String get backendName => 'ode';

  @override
  Stream<sim.SimCollisionEvent> get collisions => _collisions.stream;

  // --- helpers de conversión -------------------------------------------

  /// ODE guarda cuaterniones como (w, x, y, z); vector_math como (x, y, z, w).
  void _writeQ(Quaternion q) {
    _q[0] = q.w;
    _q[1] = q.x;
    _q[2] = q.y;
    _q[3] = q.z;
  }

  static Quaternion _readQ(ffi.Pointer<dReal> p) =>
      Quaternion(p[1], p[2], p[3], p[0]);

  static Vector3 _readV(ffi.Pointer<dReal> p) => Vector3(p[0], p[1], p[2]);

  /// Rotación ACTIVA (local → mundo). Ver `../rotation.dart`: usar
  /// `Quaternion.rotate` aquí aplica la INVERSA y corre los pivotes.
  static Vector3 _rotA(Quaternion q, Vector3 v) => rotateActive(q, v);

  _OdeBody _body(int handle) =>
      _bodies[handle] ?? (throw StateError('cuerpo $handle no existe'));

  ffi.Pointer<dxBody> _requireDBody(int handle) =>
      _body(handle).body ??
      (throw UnsupportedError(
        'el cuerpo $handle es fixed: ODE no le da dBodyID',
      ));

  // --- cuerpos ----------------------------------------------------------

  @override
  int createBody({
    required sim.PoseTarget target,
    required sim.BodyType type,
    double? additionalMass,
  }) {
    final handle = _nextHandle++;
    final rec = _OdeBody(
      type: type,
      target: target,
      additionalMass: additionalMass,
    );
    final t = target.worldTranslation;
    final r = target.worldRotation..normalize();
    rec.currPos.setFrom(t);
    rec.currRot.setFrom(r);
    rec.prevPos.setFrom(t);
    rec.prevRot.setFrom(r);

    if (type != sim.BodyType.fixed) {
      final b = _ode.dBodyCreate(_world);
      _ode.dBodySetPosition(b, t.x, t.y, t.z);
      _writeQ(r);
      _ode.dBodySetQuaternion(b, _q);
      if (type == sim.BodyType.kinematic) _ode.dBodySetKinematic(b);
      rec.body = b;
    }
    _bodies[handle] = rec;
    return handle;
  }

  @override
  void destroyBody(int bodyHandle) {
    final rec = _bodies.remove(bodyHandle);
    if (rec == null) return;
    // dBodyDestroy desengancha sus geoms; los colliders se destruyen por su
    // propio ciclo (Collider.onUnmount).
    final b = rec.body;
    if (b != null) {
      // Antes de destruirlo: el grupo va indexado por DIRECCIÓN del dBodyID, y
      // ODE reutiliza direcciones. Un cuerpo nuevo que cayera en la misma
      // dirección heredaría el grupo del muerto y dejaría de colisionar con
      // medio mundo, en silencio.
      _bodyGroup.remove(b.address);
      _ode.dBodyDestroy(b);
    }
  }

  @override
  int createAnchorBody() {
    // Anclar contra el mundo: en ODE es dJointAttach(j, b, nullptr); el
    // handle existe solo para el contrato.
    final handle = _nextHandle++;
    _bodies[handle] = _OdeBody(type: sim.BodyType.fixed, target: null);
    return handle;
  }

  @override
  void destroyAnchorBody(int bodyHandle) => _bodies.remove(bodyHandle);

  @override
  void setBodyKind(int bodyHandle, sim.BodyType type) {
    final rec = _body(bodyHandle);
    final b = rec.body;
    if (b == null || type == sim.BodyType.fixed) {
      throw UnsupportedError('ode: no se cambia de/a fixed en vivo');
    }
    if (type == sim.BodyType.kinematic) {
      _ode.dBodySetKinematic(b);
    } else {
      _ode.dBodySetDynamic(b);
    }
    rec.type = type;
  }

  @override
  (Vector3, Quaternion) readBodyPose(int bodyHandle) {
    final rec = _body(bodyHandle);
    final b = rec.body;
    if (b == null) return (rec.currPos.clone(), rec.currRot.clone());
    return (
      _readV(_ode.dBodyGetPosition(b)),
      _readQ(_ode.dBodyGetQuaternion(b)),
    );
  }

  @override
  Vector3 readBodyLinearVelocity(int bodyHandle) =>
      _readV(_ode.dBodyGetLinearVel(_requireDBody(bodyHandle)));

  @override
  Vector3 readBodyAngularVelocity(int bodyHandle) =>
      _readV(_ode.dBodyGetAngularVel(_requireDBody(bodyHandle)));

  @override
  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity) {
    final b = _requireDBody(bodyHandle);
    _wakeIfMoving(b, velocity);
    _ode.dBodySetLinearVel(b, velocity.x, velocity.y, velocity.z);
  }

  @override
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity) {
    final b = _requireDBody(bodyHandle);
    _wakeIfMoving(b, velocity);
    _ode.dBodySetAngularVel(b, velocity.x, velocity.y, velocity.z);
  }

  /// Despierta el cuerpo si se le está pidiendo movimiento.
  ///
  /// ODE NO despierta un cuerpo dormido porque le escribas la velocidad: se la
  /// guarda y sigue durmiendo. El resultado es de los que se pierden media
  /// hora persiguiendo: le das velocidad a algo y no pasa absolutamente nada,
  /// sin ningún error. Con el autodisable encendido (que es lo que hace viable
  /// el Redmi 7) eso pasa en cuanto la escena lleva un rato quieta.
  ///
  /// Escribir velocidad CERO no despierta: eso es parar algo, no moverlo.
  void _wakeIfMoving(ffi.Pointer<dxBody> b, Vector3 v) {
    if (v.length2 > 0) _ode.dBodyEnable(b);
  }

  @override
  void setBodyLinearDamping(int bodyHandle, double damping) =>
      _ode.dBodySetLinearDamping(_requireDBody(bodyHandle), damping);

  @override
  void setBodyAngularDamping(int bodyHandle, double damping) =>
      _ode.dBodySetAngularDamping(_requireDBody(bodyHandle), damping);

  @override
  void setBodyGravityScale(int bodyHandle, double scale) =>
      _ode.dBodySetGravityMode(_requireDBody(bodyHandle), scale == 0 ? 0 : 1);

  @override
  void setBodyCcdEnabled(int bodyHandle, bool enabled) {
    if (enabled) throw UnsupportedError('ode: sin CCD en el spike');
  }

  @override
  void setBodyAdditionalMass(int bodyHandle, double mass) {
    final rec = _body(bodyHandle);
    rec.additionalMass = mass;
    // Si ya tiene colliders, re-derivar la masa con TODOS ellos: mirar solo
    // el primero dejaría un compuesto pesando lo que su primera caja.
    _recomputeBodyMass(rec);
  }

  @override
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular) =>
      throw UnsupportedError('ode: sin axis locks en el spike');

  @override
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  ) {
    // Teleport simple (sin velocidad derivada): suficiente para el spike.
    final b = _requireDBody(bodyHandle);
    _ode.dBodySetPosition(b, translation.x, translation.y, translation.z);
    _writeQ(rotation..normalize());
    _ode.dBodySetQuaternion(b, _q);
  }

  @override
  void setBodyPose(int bodyHandle, Vector3 translation, Quaternion rotation) {
    // El Stop -> draft del spike. Teleport limpio: pose nueva, fuerzas y
    // pares acumulados fuera, y prev==curr para que la interpolación no
    // "viaje" desde la pose vieja.
    final rec = _body(bodyHandle);
    final b = rec.body;
    if (b == null) throw UnsupportedError('ode: setBodyPose de un fixed');
    _ode.dBodySetPosition(b, translation.x, translation.y, translation.z);
    _writeQ(rotation..normalize());
    _ode.dBodySetQuaternion(b, _q);
    _ode.dBodySetForce(b, 0, 0, 0);
    _ode.dBodySetTorque(b, 0, 0, 0);
    _ode.dBodyEnable(b);
    rec.currPos.setFrom(translation);
    rec.currRot.setFrom(rotation);
    rec.prevPos.setFrom(translation);
    rec.prevRot.setFrom(rotation);
    rec.target?.setWorldPose(translation, rotation);
  }

  @override
  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint}) {
    final b = _requireDBody(bodyHandle);
    // Igual que con la velocidad: aplicar fuerza a algo dormido no hace nada
    // en ODE si no se le despierta antes.
    _wakeIfMoving(b, force);
    if (atWorldPoint == null) {
      _ode.dBodyAddForce(b, force.x, force.y, force.z);
    } else {
      _ode.dBodyAddForceAtPos(b, force.x, force.y, force.z, atWorldPoint.x,
          atWorldPoint.y, atWorldPoint.z);
    }
  }

  @override
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint}) {
    // impulso = fuerza * dt: se aproxima aplicándolo como fuerza en el
    // próximo step. Suficiente para el spike (no se usa).
    applyForce(bodyHandle, impulse / fixedTimestep, atWorldPoint: atWorldPoint);
  }

  @override
  void applyTorque(int bodyHandle, Vector3 torque) {
    final b = _requireDBody(bodyHandle);
    _wakeIfMoving(b, torque);
    _ode.dBodyAddTorque(b, torque.x, torque.y, torque.z);
  }

  @override
  void applyAngularImpulse(int bodyHandle, Vector3 impulse) =>
      applyTorque(bodyHandle, impulse / fixedTimestep);

  @override
  bool isBodySleeping(int bodyHandle) =>
      _ode.dBodyIsEnabled(_requireDBody(bodyHandle)) == 0;

  @override
  void wakeBody(int bodyHandle) => _ode.dBodyEnable(_requireDBody(bodyHandle));

  @override
  void sleepBody(int bodyHandle) => _ode.dBodyDisable(_requireDBody(bodyHandle));

  // --- colliders --------------------------------------------------------

  @override
  List<int> createColliders(
    int bodyHandle,
    sim.Shape shape, {
    sim.PhysicsMaterial material = sim.PhysicsMaterial.defaultMaterial,
    bool isTrigger = false,
    Matrix4? localPose,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
  }) {
    if (isTrigger) {
      // Antes esto devolvía `const []`, y el componente Collider de
      // flutter_scene lanza «could not build colliders for X» cuando la lista
      // vuelve vacía: el mensaje culpaba a la FORMA teniendo la forma bien.
      throw UnsupportedError(
        'ode: este backend no tiene triggers (el shape está bien; el problema '
        'es isTrigger: true)',
      );
    }
    final rec = _body(bodyHandle);

    // Un compuesto se ABRE aquí y en ningún otro sitio: para ODE son N geoms
    // del mismo dBodyID, que es literalmente lo que `dGeomSetOffset*` hace.
    // Por eso la firma del contrato devuelve una LISTA de handles.
    final partes = <({sim.Shape shape, Matrix4 pose})>[];
    final base = localPose ?? Matrix4.identity();
    switch (shape) {
      case sim.CompoundShape(:final children):
        if (children.isEmpty) {
          throw UnsupportedError(
            'ode: un CompoundShape sin hijos no es ninguna forma',
          );
        }
        for (final child in children) {
          if (child.shape is sim.CompoundShape) {
            throw UnsupportedError(
              'ode: compuestos ANIDADOS no; aplana los hijos (la masa se '
              'acumula con el brazo de cada uno y anidar duplicaría el brazo)',
            );
          }
          partes.add((shape: child.shape, pose: base * child.localPose));
        }
      default:
        partes.add((shape: shape, pose: base));
    }

    final handles = <int>[];
    for (final parte in partes) {
      final geom = _createGeom(parte.shape);

      // La rotación que hay que darle al geom, ya con la corrección de eje del
      // cilindro si toca. Se calcula SIEMPRE, aunque localPose sea null, y se
      // usa en las DOS ramas de abajo: olvidarla en una sola deja la llanta de
      // pie como un rodillo vertical y la simulación sigue corriendo tan
      // tranquila. Es el fallo más silencioso de todo el backend.
      final localRot = (Quaternion.fromRotation(parte.pose.getRotation()))
        ..normalize();
      final geomRot = _geomRotation(parte.shape, localRot);
      final localTranslation = parte.pose.getTranslation();

      final b = rec.body;
      if (b != null) {
        _ode.dGeomSetBody(geom, b);
        // Incondicional: antes solo se hacía `if (localPose != null)`, y con un
        // cilindro sin localPose el geom se quedaba sin la corrección de eje.
        _ode.dGeomSetOffsetPosition(
            geom, localTranslation.x, localTranslation.y, localTranslation.z);
        _writeQ(geomRot);
        _ode.dGeomSetOffsetQuaternion(geom, _q);
      } else {
        // Cuerpo fixed: geom estático colocado en mundo = poseCuerpo*localPose.
        final wp = rec.currPos + _rotA(rec.currRot, localTranslation);
        final wr = (rec.currRot * geomRot)..normalize();
        _ode.dGeomSetPosition(geom, wp.x, wp.y, wp.z);
        _writeQ(wr);
        _ode.dGeomSetQuaternion(geom, _q);
      }

      final handle = _nextHandle++;
      _colliders[handle] = _OdeCollider(
        geom: geom,
        bodyHandle: bodyHandle,
        material: material,
        shape: parte.shape,
        localRot: localRot,
        localOffset: localTranslation,
      );
      _geomToCollider[geom.address] = handle;
      rec.colliderHandles.add(handle);
      handles.add(handle);
    }

    // La masa, UNA sola vez y con todos los colliders del cuerpo delante. Es
    // la corrección que hace posible el compuesto: antes se re-escribía por
    // cada collider y el último se llevaba la masa entera.
    _recomputeBodyMass(rec);
    return handles;
  }

  /// El geom de una forma PRIMITIVA. Los compuestos se abren antes.
  ffi.Pointer<dxGeom> _createGeom(sim.Shape shape) {
    switch (shape) {
      case sim.BoxShape(:final halfExtents):
        return _ode.dCreateBox(_space, halfExtents.x * 2, halfExtents.y * 2,
            halfExtents.z * 2);
      case sim.SphereShape(:final radius):
        return _ode.dCreateSphere(_space, radius);
      case sim.CylinderShape(:final radius, :final halfHeight):
        // ODE toma la ALTURA TOTAL, no la mitad. Y el cilindro de ODE va
        // alineado a su Z LOCAL, mientras que el CylinderShape del contrato va
        // alineado al Y local: la diferencia la absorbe [_geomRotation].
        return _ode.dCreateCylinder(_space, radius, halfHeight * 2);
      case sim.CapsuleShape():
        throw UnsupportedError(
          'ode: las cápsulas están PROHIBIDAS en el mecano. Se compila sin '
          'libccd, así que la pareja capsule-cylinder no está registrada y '
          'atravesaría la llanta del motor EN SILENCIO (dCollide devuelve 0 '
          'sin avisar). Usa una caja o un cilindro. Ver NATIVE.md.',
        );
      default:
        throw UnsupportedError(
          'ode: shape no soportado: ${shape.runtimeType}',
        );
    }
  }

  /// Rotación que se le da al geom, corrigiendo la convención de eje.
  ///
  /// `CylinderShape` del contrato va alineado al **Y** local del shape; el
  /// cilindro de ODE va alineado a su **Z** local. Si `Q` es la rotación de
  /// `localPose` (cuerpo←shape), hace falta una `G` con `G·(0,0,1) = Q·(0,1,0)`,
  /// y eso es `G = Q·T` con `T` mandando +Z sobre +Y.
  static Quaternion _geomRotation(sim.Shape shape, Quaternion localRot) =>
      switch (shape) {
        sim.CylinderShape() => (localRot * _zToY)..normalize(),
        _ => localRot,
      };

  /// +Z sobre +Y. `Quaternion` no es const-construible, así que vive aquí.
  static final Quaternion _zToY =
      Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2);

  /// Re-deriva la masa del cuerpo a partir de TODOS sus colliders.
  ///
  /// Con uno solo pasa por [_applyBodyMass], que es el camino de siempre y
  /// sigue dando los mismos dígitos — los veinte goldens del arnés del mecano
  /// dependen de ello. Con varios (un compuesto) va por [_applyCompoundMass],
  /// que acumula en vez de pisar.
  void _recomputeBodyMass(_OdeBody rec) {
    final b = rec.body;
    if (b == null) return;
    final cols = [for (final h in rec.colliderHandles) ?_colliders[h]];
    if (cols.isEmpty) return;
    if (cols.length == 1) {
      final c = cols.single;
      _applyBodyMass(rec, c.material, c.shape, c.localRot);
    } else {
      _applyCompoundMass(rec, cols);
    }
    // ESCRIBIR LA MASA DESHACE EL ESTADO CINEMÁTICO, y sin decir nada.
    //
    // `dBodySetKinematic` funciona poniendo `invMass` y `invI` a cero — es así
    // como la gravedad y los impactos dejan de moverlo, porque el integrador
    // multiplica las fuerzas por la inversa. `dBodySetMass` las vuelve a
    // rellenar y NO toca el flag, así que el cuerpo se queda marcado como
    // cinemático y cayéndose a la vez.
    //
    // Pasa en el orden natural: crear el cuerpo cinemático y colgarle su
    // collider después. El síntoma es una pieza fija que se cae como si nadie
    // la hubiera fijado; no hay excepción, ni log, ni NaN.
    if (rec.type == sim.BodyType.kinematic) _ode.dBodySetKinematic(b);
  }

  /// La masa y la inercia de un cuerpo hecho de VARIAS formas.
  ///
  /// Las fórmulas de cada primitiva no se re-derivan a mano: se le piden a ODE
  /// (`dMassSet*Total` sobre el struct de trabajo) y aquí solo se lleva cada
  /// tensor al frame del cuerpo —R·I·Rᵀ— y se le suma el término de Steiner
  /// `m(|d|²δ − d⊗d)`. Un número inventado que nadie contrasta es peor que
  /// ninguno.
  ///
  /// **El centro de masa TIENE que caer en el origen del cuerpo.** ODE lo fija
  /// ahí y este backend no re-centra, así que un compuesto descentrado pivotaría
  /// alrededor de un punto que no es el suyo — sin error, sin log y sin NaN. En
  /// vez de dejarlo pasar, se LANZA: quien construye la forma sabe dónde está
  /// su centroide y puede poner ahí el origen.
  void _applyCompoundMass(_OdeBody rec, List<_OdeCollider> cols) {
    final b = rec.body!;
    final volumenes = [for (final c in cols) _volumeOf(c.shape)];
    final volTotal = volumenes.fold<double>(0, (a, v) => a + v);
    if (volTotal <= 0) {
      throw StateError('ode: un compuesto de volumen cero no tiene masa');
    }

    var total = 0.0;
    final centro = Vector3.zero();
    final tensor = Matrix3.zero();

    for (var i = 0; i < cols.length; i++) {
      final col = cols[i];
      // `additionalMass` es la masa TOTAL del cuerpo: se reparte por volumen.
      final m = rec.additionalMass != null
          ? rec.additionalMass! * volumenes[i] / volTotal
          : col.material.density * volumenes[i];

      _writePrimitiveMass(m, col.shape);
      final propio = _readTensor();

      // Al frame del cuerpo, y luego el brazo.
      final llevado = _congruent(col.localRot.asRotationMatrix(), propio);
      final d = col.localOffset;
      final d2 = d.length2;
      llevado.add(Matrix3(
        m * (d2 - d.x * d.x), m * (-d.x * d.y), m * (-d.x * d.z),
        m * (-d.y * d.x), m * (d2 - d.y * d.y), m * (-d.y * d.z),
        m * (-d.z * d.x), m * (-d.z * d.y), m * (d2 - d.z * d.z),
      ));

      tensor.add(llevado);
      centro.add(d * m);
      total += m;
    }

    centro.scale(1 / total);
    if (centro.length > 1e-4) {
      throw StateError(
        'ode: el centro de masa de este compuesto cae en $centro y no en el '
        'origen del cuerpo. ODE fija el COM en el origen y aquí no se '
        're-centra: la pieza pivotaría alrededor de un punto que no es el '
        'suyo, sin dar ningún error. Construye la forma con su origen en el '
        'centroide de sus cajas.',
      );
    }

    _mass.ref.mass = total;
    for (var i = 0; i < 4; i++) {
      _mass.ref.c[i] = 0;
    }
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        _mass.ref.I[row * 4 + col] = tensor.entry(row, col);
      }
      _mass.ref.I[row * 4 + 3] = 0;
    }
    _ode.dBodySetMass(b, _mass);
  }

  /// El volumen de una primitiva, para repartir la masa total del cuerpo.
  static double _volumeOf(sim.Shape shape) => switch (shape) {
        sim.BoxShape(:final halfExtents) =>
          8 * halfExtents.x * halfExtents.y * halfExtents.z,
        sim.SphereShape(:final radius) =>
          4 / 3 * math.pi * radius * radius * radius,
        sim.CylinderShape(:final radius, :final halfHeight) =>
          math.pi * radius * radius * halfHeight * 2,
        _ => throw UnsupportedError(
            'ode: no sé el volumen de ${shape.runtimeType}',
          ),
      };

  /// Escribe en el struct de trabajo la masa de UNA primitiva, en su propio
  /// frame. Es el mismo despacho que [_applyBodyMass], sin el rotate ni el
  /// dBodySetMass: aquí el tensor se recoge y se compone a mano.
  void _writePrimitiveMass(double m, sim.Shape shape) {
    switch (shape) {
      case sim.BoxShape(:final halfExtents):
        _ode.dMassSetBoxTotal(_mass, m, halfExtents.x * 2, halfExtents.y * 2,
            halfExtents.z * 2);
      case sim.SphereShape(:final radius):
        _ode.dMassSetSphereTotal(_mass, m, radius);
      case sim.CylinderShape(:final radius, :final halfHeight):
        // 2 = Y = el eje del CylinderShape del contrato, igual que arriba.
        _ode.dMassSetCylinderTotal(_mass, m, 2, radius, halfHeight * 2);
      default:
        throw UnsupportedError(
          'ode: no sé calcular la masa de ${shape.runtimeType}',
        );
    }
  }

  /// R·I·Rᵀ: el tensor [i], expresado en otro frame.
  ///
  /// Con casts porque `Matrix3.operator *` es `dynamic` en vector_math, y una
  /// cadena sin tipar aquí dejaría pasar cualquier cosa.
  static Matrix3 _congruent(Matrix3 r, Matrix3 i) {
    final rt = r.clone()..transpose();
    return ((r * i) as Matrix3) * rt as Matrix3;
  }

  /// El tensor que ODE acaba de escribir en el struct de trabajo.
  ///
  /// Se lee por filas (0,1,2 / 4,5,6 / 8,9,10 del `dMatrix3`) y se entrega a un
  /// `Matrix3`, que es COLUMNAR. Da igual, y conviene saber por qué: un tensor
  /// de inercia es simétrico, así que leerlo transpuesto es leerlo igual.
  Matrix3 _readTensor() {
    final i = _mass.ref.I;
    return Matrix3(
      i[0], i[1], i[2],
      i[4], i[5], i[6],
      i[8], i[9], i[10],
    );
  }

  /// Masa del cuerpo a partir de su shape. `additionalMass` (el `mass:` del
  /// RigidBody) se trata como masa TOTAL; sin ella, densidad*volumen.
  ///
  /// [localRot] es la rotación del `localPose` del collider, y NO es opcional
  /// para la inercia: `dMassSet*` escribe el tensor en el frame del SHAPE, y
  /// hay que rotarlo al frame del CUERPO.
  void _applyBodyMass(
    _OdeBody rec,
    sim.PhysicsMaterial material,
    sim.Shape shape,
    Quaternion localRot,
  ) {
    final b = rec.body;
    if (b == null) return;
    switch (shape) {
      case sim.BoxShape(:final halfExtents):
        final lx = halfExtents.x * 2, ly = halfExtents.y * 2,
            lz = halfExtents.z * 2;
        final total =
            rec.additionalMass ?? material.density * lx * ly * lz;
        _ode.dMassSetBoxTotal(_mass, total, lx, ly, lz);
      case sim.SphereShape(:final radius):
        final total = rec.additionalMass ??
            material.density * 4 / 3 * math.pi * radius * radius * radius;
        _ode.dMassSetSphereTotal(_mass, total, radius);
      case sim.CylinderShape(:final radius, :final halfHeight):
        final total = rec.additionalMass ??
            material.density * math.pi * radius * radius * halfHeight * 2;
        // `direction` es 1-BASED y elige QUÉ EJE lleva el ½mr², en el frame en
        // que se pide. 2 = Y = el eje del CylinderShape del contrato. Ojo: el
        // eje del cilindro en el frame del CUERPO no tiene por qué ser Y — la
        // llanta del motor DC lo tiene en Z —, y por eso hace falta el
        // dMassRotate de abajo. Sin él la llanta se queda con
        // I = m(¼r² + L²/12) en vez de ½mr²: un 39 % menos de inercia, sin un
        // solo aviso de ODE.
        _ode.dMassSetCylinderTotal(_mass, total, 2, radius, halfHeight * 2);
      default:
        throw UnsupportedError(
          'ode: no sé calcular la masa de ${shape.runtimeType}',
        );
    }
    // Lleva el tensor del frame del shape al del cuerpo (R·I·Rᵀ).
    if (!_isIdentityRotation(localRot)) {
      _writeR(localRot);
      _ode.dMassRotate(_mass, _rot);
    }
    _ode.dBodySetMass(b, _mass);
  }

  static bool _isIdentityRotation(Quaternion q) =>
      (q.w.abs() - 1.0).abs() < 1e-9;

  /// La diagonal del tensor de inercia del cuerpo, leída de vuelta de ODE.
  ///
  /// Diagnóstico, fuera del contrato. Existe porque la inercia es lo que se
  /// equivoca en silencio: un cilindro con la masa puesta en el eje que no es
  /// pierde el 39 % de su inercia y ODE no dice nada — solo el arranque tarda
  /// otra cosa. Con esto el banco de tests puede AFIRMARLO.
  Vector3 bodyPrincipalInertia(int bodyHandle) {
    _ode.dBodyGetMass(_requireDBody(bodyHandle), _mass);
    final i = _mass.ref.I;
    // dMatrix3: 3 filas de 4; la diagonal está en 0, 5 y 10.
    return Vector3(i[0], i[5], i[10]);
  }

  /// La masa total del cuerpo, leída de vuelta de ODE.
  double bodyMass(int bodyHandle) {
    _ode.dBodyGetMass(_requireDBody(bodyHandle), _mass);
    return _mass.ref.mass;
  }

  /// Escribe una rotación en el `dMatrix3` de trabajo (3 filas de 4 floats;
  /// la cuarta columna de cada fila es padding en ODE).
  void _writeR(Quaternion q) {
    final m = q.asRotationMatrix();
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        _rot[row * 4 + col] = m.entry(row, col);
      }
      _rot[row * 4 + 3] = 0;
    }
  }

  @override
  void destroyCollider(int colliderHandle) {
    final col = _colliders.remove(colliderHandle);
    if (col == null) return;
    _geomToCollider.remove(col.geom.address);
    _bodies[col.bodyHandle]?.colliderHandles.remove(colliderHandle);
    _ode.dGeomDestroy(col.geom);
  }

  @override
  void setColliderMaterial(int colliderHandle, sim.PhysicsMaterial material) {
    _colliders[colliderHandle]?.material = material;
  }

  @override
  void setColliderFilter(int colliderHandle, int layer, int mask) {
    // Sin capas en el spike; los componentes solo lo llaman si se cambia
    // del default, y el rig no lo hace.
  }

  // --- joints -----------------------------------------------------------

  @override
  int createJoint(sim.JointDesc desc) {
    final _OdeJoint rec;
    switch (desc) {
      case sim.RevoluteJointDesc():
        final j = _ode.dJointCreateHinge(_world, ffi.nullptr);
        final swapped = _attach(j, desc.bodyA, desc.bodyB);
        // ODE toma anchor/axis en MUNDO y con los cuerpos YA en pose:
        // convertir los locals del desc con la pose actual de bodyA.
        final a = _body(desc.bodyA);
        final anchor =
            a.currPosOf(_ode) + _rotA(a.currRotOf(_ode), desc.localAnchorA);
        var axis = _rotA(a.currRotOf(_ode), desc.localAxisA)..normalize();
        // Si hubo que atar al revés (A era el mundo), el eje se niega para
        // conservar la convención del contrato: ángulo positivo = B rotando
        // respecto a A. Ver [_attach].
        if (swapped) axis = -axis;
        _ode.dJointSetHingeAnchor(j, anchor.x, anchor.y, anchor.z);
        _ode.dJointSetHingeAxis(j, axis.x, axis.y, axis.z);
        _setHingeParams(j, desc);
        rec = _OdeHinge(j, desc.bodyA, desc.bodyB,
            desc.localAnchorA.clone(), desc.localAnchorB.clone());
      case sim.FixedJointDesc():
        final j = _ode.dJointCreateFixed(_world, ffi.nullptr);
        _attach(j, desc.bodyA, desc.bodyB);
        _ode.dJointSetFixed(j); // suelda la pose relativa ACTUAL
        rec = _OdeFixed(j);
      default:
        throw UnsupportedError('ode: junta ${desc.runtimeType} fuera del spike');
    }
    final handle = _nextHandle++;
    _joints[handle] = rec;
    return handle;
  }

  /// Ata la junta. Devuelve true si hubo que INTERCAMBIAR el orden de los
  /// cuerpos, porque entonces el sentido del eje también hay que invertirlo.
  ///
  /// Un cuerpo fixed o un anchor no tiene dBodyID: en ODE eso es «el mundo»
  /// (nullptr). Y aquí está la trampa: el signo del ángulo de un hinge depende
  /// del ORDEN en que se atan los cuerpos, así que atar (mundo, cuerpo)
  /// invierte el ángulo y con él el sentido del motor, respecto a atar
  /// (cuerpo, cuerpo). Medido: con la misma velocidad objetivo +2, dos cuerpos
  /// reales dan +1.0 rad y (mundo, cuerpo) da −1.0.
  ///
  /// El contrato dice que el ángulo es el de B respecto a A alrededor de
  /// `localAxisA` —y OJO al sentido, que ODE lo niega por dentro: con ángulo
  /// +θ, B ha girado **−θ** sobre `localAxisA` (mano derecha); es A quien ha
  /// girado +θ respecto a B. Medido sobre el cuerpo en `hinge_sentido_test`.
  /// Y eso no puede depender de si A resultó ser el mundo: quien ancle una
  /// pieza al suelo obtendría el motor al revés sin enterarse. Por eso, cuando A es el mundo, se atan al revés y se niega el
  /// eje para dejar la convención donde debe estar.
  bool _attach(ffi.Pointer<dxJoint> j, int bodyA, int bodyB) {
    final a = _body(bodyA).body ?? ffi.nullptr;
    final b = _body(bodyB).body ?? ffi.nullptr;
    if (a == ffi.nullptr && b != ffi.nullptr) {
      _ode.dJointAttach(j, b, a);
      return true;
    }
    _ode.dJointAttach(j, a, b);
    return false;
  }

  void _setHingeParams(ffi.Pointer<dxJoint> j, sim.RevoluteJointDesc desc) {
    final lo = desc.lowerLimit, hi = desc.upperLimit;
    if (lo != null) _ode.dJointSetHingeParam(j, dParamLoStop, lo);
    if (hi != null) _ode.dJointSetHingeParam(j, dParamHiStop, hi);
    _ode.dJointSetHingeParam(j, dParamVel, desc.motorTargetVelocity ?? 0);
    _ode.dJointSetHingeParam(j, dParamFMax, desc.motorMaxForce ?? 0);
    // Anti-jitter clásico de ODE cuando el motor pelea contra el límite.
    _ode.dJointSetHingeParam(j, dParamFudgeFactor, 0.5);
  }

  @override
  void updateJoint(int jointHandle, sim.JointDesc desc) {
    final rec = _joints[jointHandle];
    switch ((rec, desc)) {
      case (
          final _OdeHinge h,
          final sim.RevoluteJointDesc d,
        ):
        // Solo parámetros del motor y los topes: anchor/axis NO se re-derivan,
        // porque los cuerpos ya se movieron y re-fijarlos con la pose actual
        // rompería el montaje.
        //
        // CUIDADO, y aquí es donde está la trampa: el componente RevoluteJoint
        // de flutter_scene SÍ acepta que le cambies el eje o el ancla — los
        // asigna, los normaliza y llama a push(). El que los descarta es este
        // método, sin decir nada. Así que un cambio de eje se ve aceptado por
        // arriba y no pasa nada por abajo. Al menos que se oiga:
        assert(() {
          const tol = 1e-6;
          if ((d.localAnchorA - h.requestedAnchorA).length > tol ||
              (d.localAnchorB - h.requestedAnchorB).length > tol) {
            throw StateError(
              'ode: updateJoint($jointHandle) trae anclas distintas de las de '
              'creación y este backend NO las re-deriva. Destruye la junta y '
              'créala de nuevo.',
            );
          }
          return true;
        }());
        _setHingeParams(h.joint, d);
      case (_OdeFixed(), sim.FixedJointDesc()):
        break; // nada reconfigurable
      default:
        throw UnsupportedError('ode: updateJoint incompatible');
    }
  }

  @override
  void destroyJoint(int jointHandle) {
    final rec = _joints.remove(jointHandle);
    if (rec != null) _ode.dJointDestroy(rec.joint);
  }

  /// Ángulo actual del hinge (radianes, 0 = pose de creación). Fuera del
  /// contrato: el controlador P del servo lo lee vía downcast.
  double hingeAngle(int jointHandle) => switch (_joints[jointHandle]) {
        _OdeHinge(:final joint) => _ode.dJointGetHingeAngle(joint),
        _ => throw StateError('hingeAngle: $jointHandle no es un hinge'),
      };

  double hingeAngleRate(int jointHandle) => switch (_joints[jointHandle]) {
        _OdeHinge(:final joint) => _ode.dJointGetHingeAngleRate(joint),
        _ => throw StateError('hingeAngleRate: $jointHandle no es un hinge'),
      };

  /// El ancla en MUNDO que ODE tiene para este hinge, tal cual.
  ///
  /// Diagnóstico, fuera del contrato. Sirve para contrastar lo que se PIDIÓ
  /// contra lo que llegó: es la comprobación que caza una conversión
  /// local→mundo hecha con la rotación invertida, que es un fallo que ni ODE
  /// ni el render denuncian (el modelo se ve casi bien y el solver mantiene
  /// sus anclas juntas... alrededor del pivote equivocado).
  Vector3 debugHingeAnchor(int jointHandle) => switch (_joints[jointHandle]) {
        _OdeHinge(:final joint) => () {
            _ode.dJointGetHingeAnchor(joint, _v3a);
            return _readV(_v3a);
          }(),
        _ => throw StateError('debugHingeAnchor: $jointHandle no es un hinge'),
      };

  // --- colisión ---------------------------------------------------------

  void _near(ffi.Pointer<ffi.Void> data, ffi.Pointer<dxGeom> o1,
      ffi.Pointer<dxGeom> o2) {
    final b1 = _ode.dGeomGetBody(o1);
    final b2 = _ode.dGeomGetBody(o2);
    if (b1 == ffi.nullptr && b2 == ffi.nullptr) return;
    if (b1 != ffi.nullptr && b2 != ffi.nullptr) {
      if (_ode.dAreConnectedExcluding(
              b1, b2, dJointType.dJointTypeContact.value) !=
          0) {
        return; // unidos por hinge/fixed: sin contactos entre sí
      }
      final g1 = _bodyGroup[b1.address] ?? 0;
      if (g1 != 0 && g1 == (_bodyGroup[b2.address] ?? 0)) {
        return; // mismo mecanismo: sin contactos internos
      }
    }

    final n = _ode.dCollide(o1, o2, _maxContacts, _contactGeoms,
        ffi.sizeOf<dContactGeom>());
    if (n == 0) return;

    // Alimenta la telemetría. `nc` es el coste real del LCP (cylinder-box es
    // un SAT y devuelve hasta 8 contactos donde una esfera devuelve 1), y
    // `pen` es el diagnóstico que separa dos fallos que se parecen: en sierra
    // significa resonancia, creciente significa que algo se está hundiendo.
    if (n > _maxContacts_) _maxContacts_ = n;
    for (var i = 0; i < n; i++) {
      final d = _contactGeoms[i].depth;
      if (d > _maxPenetration) _maxPenetration = d;
    }

    // Quién está tocando algo. Se anota AQUÍ y no antes del `dCollide` a
    // propósito: arriba solo se sabe que dos cajas envolventes se cruzaron,
    // y `n == 0` ya salió por su propio `return`. Los dos descartes de
    // arriba —junta común y mismo mecanismo— son los que le dan el
    // significado «algo AJENO».
    var pen = 0.0;
    for (var i = 0; i < n; i++) {
      final d = _contactGeoms[i].depth;
      if (d > pen) pen = d;
    }
    if (b1 != ffi.nullptr) {
      final prev = _touching[b1.address];
      if (prev == null || pen > prev) _touching[b1.address] = pen;
    }
    if (b2 != ffi.nullptr) {
      final prev = _touching[b2.address];
      if (prev == null || pen > prev) _touching[b2.address] = pen;
    }

    // Fricción: promedio de los materiales de ambos geoms, salvo que uno de
    // los dos pida `min` (ver la cabecera): entonces manda el que menos roza.
    double mu = 0.8;
    final c1 = _colliders[_geomToCollider[o1.address] ?? -1];
    final c2 = _colliders[_geomToCollider[o2.address] ?? -1];
    if (c1 != null && c2 != null) {
      final m1 = c1.material, m2 = c2.material;
      mu = (m1.frictionCombine == sim.CombineRule.min || m2.frictionCombine == sim.CombineRule.min)
          ? math.min(m1.friction, m2.friction)
          : (m1.friction + m2.friction) / 2;
    }

    for (var i = 0; i < n; i++) {
      final src = _contactGeoms[i];
      final dst = _contact.ref;
      dst.surface.mode = dContactApprox1 | dContactSoftCFM;
      dst.surface.mu = mu;
      dst.surface.soft_cfm = 1e-4;
      dst.geom.pos[0] = src.pos[0];
      dst.geom.pos[1] = src.pos[1];
      dst.geom.pos[2] = src.pos[2];
      dst.geom.normal[0] = src.normal[0];
      dst.geom.normal[1] = src.normal[1];
      dst.geom.normal[2] = src.normal[2];
      dst.geom.depth = src.depth;
      dst.geom.g1 = src.g1;
      dst.geom.g2 = src.g2;
      final j = _ode.dJointCreateContact(_world, _contactGroup, _contact);
      _ode.dJointAttach(j, b1, b2);
    }
  }

  // --- stepping ---------------------------------------------------------

  /// Dónde van las líneas de telemetría. Mutable: se enciende y se apaga con
  /// la escena corriendo.
  OdeTelemetrySink? telemetry;

  /// Cada cuántos segundos de SIMULACIÓN se emite una línea.
  double telemetryPeriod;

  double _simTime = 0;
  double _nextEmit = 0;

  /// **EL RELOJ DE LA SIMULACIÓN**: cuántos segundos de mundo se han vivido.
  ///
  /// No es el reloj de pared, y esa diferencia es justo el motivo de que este
  /// getter exista. La física la tiquea el renderer con el `frameDt` que le
  /// toque, y cuando el fotograma tarda más de lo que caben en
  /// `maxSubsteps`, **el tiempo sobrante se tira**. Por debajo de unos 15 fps
  /// el mundo avanza más despacio que el reloj de la pared, sin un solo aviso.
  ///
  /// Lo sabía la telemetría —es el `t=` de cada línea `ode t=…`— y nadie más.
  /// El concurso lo necesita por dos cosas: para poner la hora en el acta (un
  /// tiempo de vuelta medido a reloj de pared dependería de lo cargado que
  /// estuviera el servidor esa tarde) y para poder comprobar si la máquina
  /// siguió el ritmo, comparándolo con el reloj de verdad.
  double get simTime => _simTime;

  /// Acumuladores del tramo entre dos líneas, alimentados desde [_near].
  double _maxPenetration = 0;
  int _maxContacts_ = 0;

  @override
  void step(double fixedDt) {
    if (_disposed || paused) return;
    // AL PRINCIPIO. Ver [_touching]: al final dejaría el mapa vacío para todo
    // el que lo consulte entre pasos, que son todos.
    _touching.clear();
    _ode.dWorldSetGravity(_world, gravity.x, gravity.y, gravity.z);

    for (final rec in _bodies.values) {
      if (rec.type == sim.BodyType.dynamic_ && rec.body != null) {
        rec.prevPos.setFrom(rec.currPos);
        rec.prevRot.setFrom(rec.currRot);
      }
    }

    _ode.dSpaceCollide(_space, ffi.nullptr, _nearCallable.nativeFunction);
    _ode.dWorldQuickStep(_world, fixedDt);
    _ode.dJointGroupEmpty(_contactGroup);

    for (final rec in _bodies.values) {
      final b = rec.body;
      if (rec.type == sim.BodyType.dynamic_ && b != null) {
        rec.currPos.setFrom(_readV(_ode.dBodyGetPosition(b)));
        rec.currRot.setFrom(_readQ(_ode.dBodyGetQuaternion(b)));
      }
    }

    // DESPUÉS del step, no antes: en el spike la línea `t=6.0s` describía el
    // estado de t=5.996 y eso confunde justo cuando se compara con capturas.
    _simTime += fixedDt;
    final sink = telemetry;
    if (sink != null && _simTime >= _nextEmit) {
      _nextEmit = _simTime + telemetryPeriod;
      _emitTelemetry(sink);
      _maxPenetration = 0;
      _maxContacts_ = 0;
    }
  }

  void _emitTelemetry(OdeTelemetrySink sink) {
    final bodies = <OdeBodySample>[];
    for (final e in _bodies.entries) {
      final body = e.value.body;
      if (e.value.type != sim.BodyType.dynamic_ || body == null) continue;
      final p = _readV(_ode.dBodyGetPosition(body));
      bodies.add(OdeBodySample(
        handle: e.key,
        x: p.x,
        y: p.y,
        z: p.z,
        speed: _readV(_ode.dBodyGetLinearVel(body)).length,
        spin: _readV(_ode.dBodyGetAngularVel(body)).length,
        sleeping: _ode.dBodyIsEnabled(body) == 0,
      ));
    }

    final hinges = <OdeHingeSample>[];
    for (final e in _joints.entries) {
      if (e.value case _OdeHinge(
        :final joint,
        :final bodyA,
        :final bodyB,
        :final requestedAnchorA,
        :final requestedAnchorB,
      )) {
        final a = _bodies[bodyA];
        final bb = _bodies[bodyB];
        if (a == null || bb == null) continue;
        // A: el ancla que se PIDIÓ, vista desde cada cuerpo. Es lo único que
        // habría cazado el cuaternión invertido: aquel bug dejaba los dos
        // cuerpos consistentes ENTRE SÍ, así que el gap del solver era 0 y
        // solo este delataba que el pivote estaba corrido.
        final wa = a.currPosOf(_ode) + _rotA(a.currRotOf(_ode), requestedAnchorA);
        final wb = bb.currPosOf(_ode) + _rotA(bb.currRotOf(_ode), requestedAnchorB);
        // B: las anclas que ODE mantiene. Separadas = violación del solver.
        _ode.dJointGetHingeAnchor(joint, _v3a);
        _ode.dJointGetHingeAnchor2(joint, _v3b);
        final solverGap = (_readV(_v3a) - _readV(_v3b)).length;
        hinges.add(OdeHingeSample(
          handle: e.key,
          gapRequested: (wa - wb).length,
          gapSolver: solverGap,
          angle: _ode.dJointGetHingeAngle(joint),
          rate: _ode.dJointGetHingeAngleRate(joint),
        ));
      }
    }

    sink(formatOdeTelemetry(
      simTime: _simTime,
      maxPenetration: _maxPenetration,
      maxContacts: _maxContacts_,
      bodies: bodies,
      hinges: hinges,
    ));

    // Guardia de NaN: «sin NaN» pasa de ser algo que alguien mira en el HUD a
    // algo que la máquina afirma. Y se PAUSA, porque una vez que un cuerpo es
    // NaN el resto del mundo se contagia y la línea siguiente ya no dice nada.
    for (final s in bodies) {
      if (!s.finite) {
        sink('ode NaN en el cuerpo ${s.handle} — simulación PAUSADA');
        paused = true;
        return;
      }
    }
  }

  @override
  void interpolatePoses(double alpha) {
    if (_disposed) return;
    for (final rec in _bodies.values) {
      final target = rec.target;
      if (target == null ||
          rec.type != sim.BodyType.dynamic_ ||
          rec.body == null) {
        continue;
      }
      final pos = lerpPosition(rec.prevPos, rec.currPos, alpha);
      final rot = nlerpShortest(rec.prevRot, rec.currRot, alpha);
      target.setWorldPose(pos, rot);
    }
  }

  // --- queries -----------------------------------------------------------

  /// Núcleo compartido de [raycast]/[raycastAll]: todos los impactos, sin
  /// ordenar. `distance` va en unidades de MUNDO sobre la dirección
  /// normalizada (dGeomRaySet normaliza él mismo), NO en el parámetro `t` de
  /// `Ray.at(t)` — la `direction` de vector_math no está normalizada por
  /// contrato.
  List<sim.SimRaycastHit> _raycastHits(
    Ray ray,
    double maxDistance,
    int layerMask,
    bool includeFixed,
    bool includeKinematic,
    bool includeDynamic,
  ) {
    // Sin capas: todo collider es capa 1 (mismo trato que setColliderFilter,
    // que es no-op).
    if ((layerMask & 1) == 0) return const [];
    // Dirección cero: en este build (dNODEBUG) dNormalize3 NO falla — deja
    // (1,0,0) EN SILENCIO y devolvería impactos reales hacia +X.
    if (ray.direction.length2 == 0) return const [];
    if (maxDistance <= 0) return const [];

    // dInfinity también pasaría los cortes de los colliders, pero
    // dxRay::computeAABB haría 0*inf = NaN el día que el rayo entrara a un
    // espacio; 1e6 es exactamente representable en single (< 2^24).
    final length = maxDistance.isFinite ? maxDistance : 1e6;
    final rg = _rayGeom ??= _ode.dCreateRay(ffi.nullptr, 1);
    _ode.dGeomRaySetLength(rg, length);
    final o = ray.origin;
    final d = ray.direction;
    _ode.dGeomRaySet(rg, o.x, o.y, o.z, d.x, d.y, d.z);

    final hits = <sim.SimRaycastHit>[];
    for (final entry in _colliders.entries) {
      final c = entry.value;
      // `?.`, no `!`: destroyBody no toca _colliders y deja colliders
      // huérfanos vivos y colisionables; ODE les hizo dGeomSetBody(geom, 0),
      // así que se tratan como fixed, que es lo que son ya para el mundo.
      final type = _bodies[c.bodyHandle]?.type ?? sim.BodyType.fixed;
      final included = switch (type) {
        sim.BodyType.fixed => includeFixed,
        sim.BodyType.kinematic => includeKinematic,
        sim.BodyType.dynamic_ => includeDynamic,
      };
      if (!included) continue;
      // El rayo SIEMPRE como o1: la pareja inversa está registrada con
      // reverse=1 y ODE invertiría la normal en silencio.
      final n = _ode.dCollide(
          rg, c.geom, 1, _rayContact, ffi.sizeOf<dContactGeom>());
      if (n == 0) continue;
      final src = _rayContact.ref;
      hits.add(sim.SimRaycastHit(
        colliderHandle: entry.key,
        worldPoint: Vector3(src.pos[0], src.pos[1], src.pos[2]),
        worldNormal: Vector3(src.normal[0], src.normal[1], src.normal[2]),
        distance: src.depth,
      ));
    }
    return hits;
  }

  // `includeTriggers` se ignora en ambos: createColliders LANZA con
  // isTrigger:true, así que nunca hay triggers en este backend.

  @override
  sim.SimRaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    if (_disposed) return null;
    sim.SimRaycastHit? best;
    for (final hit in _raycastHits(ray, maxDistance, layerMask, includeFixed,
        includeKinematic, includeDynamic)) {
      if (best == null || hit.distance < best.distance) best = hit;
    }
    return best;
  }

  @override
  List<sim.SimRaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    if (_disposed) return const [];
    final hits = _raycastHits(ray, maxDistance, layerMask, includeFixed,
        includeKinematic, includeDynamic);
    // Los caminos de guardia devuelven `const []`, que no admite sort.
    if (hits.length > 1) hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  @override
  List<sim.SimOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) =>
      const [];

  @override
  List<sim.SimOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) =>
      const [];

  @override
  sim.SimShapeCastHit? shapeCast(
    sim.Shape shape,
    Matrix4 from,
    Vector3 direction,
    double distance, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) =>
      null;

  // --- fin de vida ------------------------------------------------------

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final j in _joints.values) {
      _ode.dJointDestroy(j.joint);
    }
    _joints.clear();
    for (final c in _colliders.values) {
      _ode.dGeomDestroy(c.geom);
    }
    final rg = _rayGeom;
    if (rg != null) _ode.dGeomDestroy(rg);
    _colliders.clear();
    _geomToCollider.clear();
    for (final b in _bodies.values) {
      final p = b.body;
      if (p != null) _ode.dBodyDestroy(p);
    }
    _bodies.clear();
    _bodyGroup.clear();
    _touching.clear();
    _ode.dJointGroupDestroy(_contactGroup);
    _ode.dSpaceDestroy(_space);
    _ode.dWorldDestroy(_world);
    _ode.dCloseODE();
    _nearCallable.close();
    calloc.free(_contactGeoms);
    calloc.free(_contact);
    calloc.free(_q);
    calloc.free(_mass);
    calloc.free(_v3a);
    calloc.free(_v3b);
    calloc.free(_rot);
    calloc.free(_rayContact);
    _collisions.close();
  }
}

extension on _OdeBody {
  /// Pose FRESCA del cuerpo (no la del último step): para derivar anchors.
  Vector3 currPosOf(OdeBindings ode) {
    final b = body;
    if (b == null) return currPos.clone();
    final p = ode.dBodyGetPosition(b);
    return Vector3(p[0], p[1], p[2]);
  }

  Quaternion currRotOf(OdeBindings ode) {
    final b = body;
    if (b == null) return currRot.clone();
    final q = ode.dBodyGetQuaternion(b);
    return Quaternion(q[1], q[2], q[3], q[0]);
  }
}

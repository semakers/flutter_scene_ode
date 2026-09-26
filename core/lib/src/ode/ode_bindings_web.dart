// GENERADO por tool/gen_bindings_web.dart. No editar a mano.
//
// El gemelo web de ode_bindings_ffi.dart: las MISMAS clases con las mismas
// firmas, sobre los exports del módulo wasm en vez de sobre símbolos de una
// librería dinámica. Las firmas se copian del fichero de ffigen y la lista de
// funciones sale de ffigen.template.yaml, así que las dos ramas no pueden
// derivar sin que alguien se entere.
//
// Los desplazamientos y tamaños son los de wasm32 (ILP32), MEDIDOS por
// tool/wasm/nairda_ode_layout.cpp desde dentro del propio módulo y volcados a
// tool/ode_wasm_layout.json. No hay ni un número supuesto: el cargador vuelve a
// preguntárselos al módulo que carga y aborta si no cuadran.
//
// ignore_for_file: non_constant_identifier_names, camel_case_types
// ignore_for_file: constant_identifier_names
// ignore_for_file: library_private_types_in_public_api
library;

import 'dart:js_interop';

import 'ffi_shim_web.dart';

export 'ffi_shim_web.dart' show DynamicLibrary;

// Tipos opacos: nunca se desreferencian, solo viajan como direcciones.
// Que sean tipos DISTINTOS es lo que impide pasar un cuerpo donde va un geom.
abstract class dxWorld implements NativeType {}
abstract class dxSpace implements NativeType {}
abstract class dxBody implements NativeType {}
abstract class dxGeom implements NativeType {}
abstract class dxJoint implements NativeType {}
abstract class dxJointGroup implements NativeType {}

/// Precisión SIMPLE, igual que en la rama nativa. Si esto fuera `Double` el
/// módulo no daría error de enlace: leería basura.
typedef dReal = Float;
typedef DartdReal = double;
typedef dNearCallback
    = NativeFunction<Void Function(Pointer<Void>, Pointer<dxGeom>, Pointer<dxGeom>)>;

// Constantes copiadas de los bindings de ffigen: son enteros y no dependen
// de la ABI, así que aquí valen lo mismo.
const int FP_NAN = 0;
const int FP_INFINITE = 1;
const int FP_ZERO = 2;
const int FP_SUBNORMAL = 3;
const int FP_NORMAL = 4;
const int d_ERR_UNKNOWN = 0;
const int d_ERR_IASSERT = 1;
const int d_ERR_UASSERT = 2;
const int d_ERR_LCP = 3;
const int dParamLoStop = 0;
const int dParamHiStop = 1;
const int dParamVel = 2;
const int dParamLoVel = 3;
const int dParamHiVel = 4;
const int dParamFMax = 5;
const int dParamFudgeFactor = 6;
const int dParamBounce = 7;
const int dParamCFM = 8;
const int dParamStopERP = 9;
const int dParamStopCFM = 10;
const int dParamSuspensionERP = 11;
const int dParamSuspensionCFM = 12;
const int dParamERP = 13;
const int dParamsInGroup = 14;
const int dParamGroup1 = 0;
const int dParamLoStop1 = 0;
const int dParamHiStop1 = 1;
const int dParamVel1 = 2;
const int dParamLoVel1 = 3;
const int dParamHiVel1 = 4;
const int dParamFMax1 = 5;
const int dParamFudgeFactor1 = 6;
const int dParamBounce1 = 7;
const int dParamCFM1 = 8;
const int dParamStopERP1 = 9;
const int dParamStopCFM1 = 10;
const int dParamSuspensionERP1 = 11;
const int dParamSuspensionCFM1 = 12;
const int dParamERP1 = 13;
const int dParamGroup2 = 256;
const int dParamLoStop2 = 256;
const int dParamHiStop2 = 257;
const int dParamVel2 = 258;
const int dParamLoVel2 = 259;
const int dParamHiVel2 = 260;
const int dParamFMax2 = 261;
const int dParamFudgeFactor2 = 262;
const int dParamBounce2 = 263;
const int dParamCFM2 = 264;
const int dParamStopERP2 = 265;
const int dParamStopCFM2 = 266;
const int dParamSuspensionERP2 = 267;
const int dParamSuspensionCFM2 = 268;
const int dParamERP2 = 269;
const int dParamGroup3 = 512;
const int dParamLoStop3 = 512;
const int dParamHiStop3 = 513;
const int dParamVel3 = 514;
const int dParamLoVel3 = 515;
const int dParamHiVel3 = 516;
const int dParamFMax3 = 517;
const int dParamFudgeFactor3 = 518;
const int dParamBounce3 = 519;
const int dParamCFM3 = 520;
const int dParamStopERP3 = 521;
const int dParamStopCFM3 = 522;
const int dParamSuspensionERP3 = 523;
const int dParamSuspensionCFM3 = 524;
const int dParamERP3 = 525;
const int dParamGroup = 256;
const int dAMotorUser = 0;
const int dAMotorEuler = 1;
const int dTransmissionParallelAxes = 0;
const int dTransmissionIntersectingAxes = 1;
const int dTransmissionChainDrive = 2;
const int dContactMu2 = 1;
const int dContactAxisDep = 1;
const int dContactFDir1 = 2;
const int dContactBounce = 4;
const int dContactSoftERP = 8;
const int dContactSoftCFM = 16;
const int dContactMotion1 = 32;
const int dContactMotion2 = 64;
const int dContactMotionN = 128;
const int dContactSlip1 = 256;
const int dContactSlip2 = 512;
const int dContactRolling = 1024;
const int dContactApprox0 = 0;
const int dContactApprox1_1 = 4096;
const int dContactApprox1_2 = 8192;
const int dContactApprox1_N = 16384;
const int dContactApprox1 = 28672;
const int dWSTP_WorldIslandsIterationMaxThreads = 1;
const int dWSTP_IslandSteppingMaxThreads = 2;
const int dWSTP_LCPSolvingMaxThreads = 4;
const int dGeomCommonControlClass = 0;
const int dGeomColliderControlClass = 1;
const int dGeomCommonAnyControlCode = 0;
const int dGeomColliderSetMergeSphereContactsControlCode = 1;
const int dGeomColliderGetMergeSphereContactsControlCode = 2;
const int dGeomColliderMergeContactsValue__Default = 0;
const int dGeomColliderMergeContactsValue_None = 1;
const int dGeomColliderMergeContactsValue_Normals = 2;
const int dGeomColliderMergeContactsValue_Full = 3;
const int dMaxUserClasses = 4;
const int dSphereClass = 0;
const int dBoxClass = 1;
const int dCapsuleClass = 2;
const int dCylinderClass = 3;
const int dPlaneClass = 4;
const int dRayClass = 5;
const int dConvexClass = 6;
const int dGeomTransformClass = 7;
const int dTriMeshClass = 8;
const int dHeightfieldClass = 9;
const int dFirstSpaceClass = 10;
const int dSimpleSpaceClass = 10;
const int dHashSpaceClass = 11;
const int dSweepAndPruneSpaceClass = 12;
const int dQuadTreeSpaceClass = 13;
const int dLastSpaceClass = 13;
const int dFirstUserClass = 14;
const int dLastUserClass = 17;
const int dGeomNumClasses = 18;
const int dTRIMESHDATA__MIN = 0;
const int dTRIMESHDATA_FACE_NORMALS = 0;
const int dTRIMESHDATA_USE_FLAGS = 1;
const int dTRIMESHDATA__MAX = 2;
const int TRIMESH_FACE_NORMALS = 0;
const int dMESHDATAUSE_EDGE1 = 1;
const int dMESHDATAUSE_EDGE2 = 2;
const int dMESHDATAUSE_EDGE3 = 4;
const int dMESHDATAUSE_VERTEX1 = 8;
const int dMESHDATAUSE_VERTEX2 = 16;
const int dMESHDATAUSE_VERTEX3 = 32;
const int dTRIDATAPREPROCESS_BUILD__MIN = 0;
const int dTRIDATAPREPROCESS_BUILD_CONCAVE_EDGES = 0;
const int dTRIDATAPREPROCESS_BUILD_FACE_ANGLES = 1;
const int dTRIDATAPREPROCESS_BUILD__MAX = 2;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA__MIN = 0;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA_BYTE_POSITIVE = 0;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA_BYTE_ALL = 1;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA_WORD_ALL = 2;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA__MAX = 3;
const int dTRIDATAPREPROCESS_FACE_ANGLES_EXTRA__DEFAULT = 0;

enum dSpaceAxis {
  dSA__MIN(0),
  dSA_Y(1),
  dSA_Z(2),
  dSA__MAX(3);

  const dSpaceAxis(this.value);
  final int value;
}

enum dMotionDynamics {
  dMD__MIN(0),
  dMD_ANGULAR(1),
  dMD__MAX(2);

  const dMotionDynamics(this.value);
  final int value;
}

enum dDynamicsAxis {
  dDA__MIN(0),
  dDA_LY(1),
  dDA_LZ(2),
  dDA__L_MAX(3),
  dDA_AY(4),
  dDA_AZ(5),
  dDA__A_MAX(6);

  const dDynamicsAxis(this.value);
  final int value;
}

enum dVec3Element {
  dV3E__MIN(0),
  dV3E_Y(1),
  dV3E_Z(2),
  dV3E__AXES_MAX(3),
  dV3E__MAX(4);

  const dVec3Element(this.value);
  final int value;
}

enum dVec4Element {
  dV4E__MIN(0),
  dV4E_Y(1),
  dV4E_Z(2),
  dV4E_O(3),
  dV4E__MAX(4);

  const dVec4Element(this.value);
  final int value;
}

enum dMat3Element {
  dM3E__MIN(0),
  dM3E_XY(1),
  dM3E_XZ(2),
  dM3E__X_AXES_MAX(3),
  dM3E__X_MAX(4),
  dM3E_YY(5),
  dM3E_YZ(6),
  dM3E__Y_AXES_MAX(7),
  dM3E__Y_MAX(8),
  dM3E_ZY(9),
  dM3E_ZZ(10),
  dM3E__Z_AXES_MAX(11),
  dM3E__Z_MAX(12);

  const dMat3Element(this.value);
  final int value;
}

enum dMat4Element {
  dM4E__MIN(0),
  dM4E_XY(1),
  dM4E_XZ(2),
  dM4E_XO(3),
  dM4E__X_MAX(4),
  dM4E_YY(5),
  dM4E_YZ(6),
  dM4E_YO(7),
  dM4E__Y_MAX(8),
  dM4E_ZY(9),
  dM4E_ZZ(10),
  dM4E_ZO(11),
  dM4E__Z_MAX(12),
  dM4E_OY(13),
  dM4E_OZ(14),
  dM4E_OO(15),
  dM4E__O_MAX(16);

  const dMat4Element(this.value);
  final int value;
}

enum dQuatElement {
  dQUE__MIN(0),
  dQUE__AXIS_MIN(1),
  dQUE_J(2),
  dQUE_K(3),
  dQUE__AXIS_MAX(4);

  const dQuatElement(this.value);
  final int value;
}

enum dJointType {
  dJointTypeNone(0),
  dJointTypeBall(1),
  dJointTypeHinge(2),
  dJointTypeSlider(3),
  dJointTypeContact(4),
  dJointTypeUniversal(5),
  dJointTypeHinge2(6),
  dJointTypeFixed(7),
  dJointTypeNull(8),
  dJointTypeAMotor(9),
  dJointTypeLMotor(10),
  dJointTypePlane2D(11),
  dJointTypePR(12),
  dJointTypePU(13),
  dJointTypePiston(14),
  dJointTypeDBall(15),
  dJointTypeDHinge(16),
  dJointTypeTransmission(17);

  const dJointType(this.value);
  final int value;
}

enum dInitODEFlags {
  dInitFlagManualThreadCleanup(1);

  const dInitODEFlags(this.value);
  final int value;
}

enum dAllocateODEDataFlags {
  dAllocateFlagBasicData(0),
  dAllocateFlagCollisionData(1),
  dAllocateMaskAll(-1);

  const dAllocateODEDataFlags(this.value);
  final int value;
}

enum dMeshTriangleVertex {
  dMTV__MIN(0),
  dMTV_SECOND(1),
  dMTV_THIRD(2),
  dMTV__MAX(3);

  const dMeshTriangleVertex(this.value);
  final int value;
}

// Los structs son CLASES, no extension types, y eso NO es un detalle de estilo:
// un extension type se borra en ejecución (su tipo reificado es el de la
// representación), así que `sizeOf<dContactGeom>()` vería `T == int` y
// devolvería el tamaño equivocado sin dar ningún error.

/// Parámetros de superficie del contacto. Vista sobre `dirección + campo`.
class dSurfaceParameters implements NativeType {
  dSurfaceParameters(this._a);
  final int _a;

  int get mode => odeHeap.getI32(_a + 0);
  set mode(int v) => odeHeap.setI32(_a + 0, v);
  double get mu => odeHeap.getF32(_a + 4);
  set mu(double v) => odeHeap.setF32(_a + 4, v);
  double get mu2 => odeHeap.getF32(_a + 8);
  set mu2(double v) => odeHeap.setF32(_a + 8, v);
  double get rho => odeHeap.getF32(_a + 12);
  set rho(double v) => odeHeap.setF32(_a + 12, v);
  double get rho2 => odeHeap.getF32(_a + 16);
  set rho2(double v) => odeHeap.setF32(_a + 16, v);
  double get rhoN => odeHeap.getF32(_a + 20);
  set rhoN(double v) => odeHeap.setF32(_a + 20, v);
  double get bounce => odeHeap.getF32(_a + 24);
  set bounce(double v) => odeHeap.setF32(_a + 24, v);
  double get bounce_vel => odeHeap.getF32(_a + 28);
  set bounce_vel(double v) => odeHeap.setF32(_a + 28, v);
  double get soft_erp => odeHeap.getF32(_a + 32);
  set soft_erp(double v) => odeHeap.setF32(_a + 32, v);
  double get soft_cfm => odeHeap.getF32(_a + 36);
  set soft_cfm(double v) => odeHeap.setF32(_a + 36, v);
  double get motion1 => odeHeap.getF32(_a + 40);
  set motion1(double v) => odeHeap.setF32(_a + 40, v);
  double get motion2 => odeHeap.getF32(_a + 44);
  set motion2(double v) => odeHeap.setF32(_a + 44, v);
  double get motionN => odeHeap.getF32(_a + 48);
  set motionN(double v) => odeHeap.setF32(_a + 48, v);
  double get slip1 => odeHeap.getF32(_a + 52);
  set slip1(double v) => odeHeap.setF32(_a + 52, v);
  double get slip2 => odeHeap.getF32(_a + 56);
  set slip2(double v) => odeHeap.setF32(_a + 56, v);
}

/// Un punto de contacto entre dos geoms.
class dContactGeom implements NativeType {
  dContactGeom(this._a);
  final int _a;

  Array<dReal> get pos => Array<dReal>(_a + 0);
  Array<dReal> get normal => Array<dReal>(_a + 16);
  double get depth => odeHeap.getF32(_a + 32);
  set depth(double v) => odeHeap.setF32(_a + 32, v);
  Pointer<dxGeom> get g1 => Pointer<dxGeom>(odeHeap.getI32(_a + 36));
  set g1(Pointer<dxGeom> v) => odeHeap.setI32(_a + 36, v.address);
  Pointer<dxGeom> get g2 => Pointer<dxGeom>(odeHeap.getI32(_a + 40));
  set g2(Pointer<dxGeom> v) => odeHeap.setI32(_a + 40, v.address);
  int get side1 => odeHeap.getI32(_a + 44);
  int get side2 => odeHeap.getI32(_a + 48);
}

/// El contacto entero, tal como lo pide `dJointCreateContact`.
class dContact implements NativeType {
  dContact(this._a);
  final int _a;

  dSurfaceParameters get surface => dSurfaceParameters(_a + 0);
  dContactGeom get geom => dContactGeom(_a + 60);
  Array<dReal> get fdir1 => Array<dReal>(_a + 112);
}

/// La masa y el tensor de inercia.
class dMass implements NativeType {
  dMass(this._a);
  final int _a;

  double get mass => odeHeap.getF32(_a + 0);
  set mass(double v) => odeHeap.setF32(_a + 0, v);
  Array<dReal> get c => Array<dReal>(_a + 4);
  Array<dReal> get I => Array<dReal>(_a + 20);
}

// `.ref` y `p[i]` sobre punteros a struct. En `dart:ffi` esto es magia del
// compilador; aquí hace falta una extensión por tipo, que es barato porque los
// structs son exactamente cuatro.
extension DSurfaceParametersPointer on Pointer<dSurfaceParameters> {
  dSurfaceParameters get ref => dSurfaceParameters(address);
}

extension DContactGeomPointer on Pointer<dContactGeom> {
  dContactGeom get ref => dContactGeom(address);
  dContactGeom operator [](int i) =>
      dContactGeom(address + i * 52);
}

extension DContactPointer on Pointer<dContact> {
  dContact get ref => dContact(address);
  dContact operator [](int i) => dContact(address + i * 128);
}

extension DMassPointer on Pointer<dMass> {
  dMass get ref => dMass(address);
  dMass operator [](int i) => dMass(address + i * 68);
}

/// El layout ENTERO con el que se generó este fichero.
///
/// El cargador se lo vuelve a preguntar al módulo que carga y aborta si no
/// cuadra: así «el ode.wasm de assets/ es de hace tres semanas» se nota al
/// arrancar y no como una física que se mueve raro.
const Map<String, int> odeGeneratedLayout = {
  'dContact.fdir1': 112,
  'dContact.geom': 60,
  'dContact.surface': 0,
  'dContactGeom.depth': 32,
  'dContactGeom.g1': 36,
  'dContactGeom.g2': 40,
  'dContactGeom.normal': 16,
  'dContactGeom.pos': 0,
  'dContactGeom.side1': 44,
  'dContactGeom.side2': 48,
  'dMass.I': 20,
  'dMass.c': 4,
  'dMass.mass': 0,
  'dSurfaceParameters.bounce': 24,
  'dSurfaceParameters.bounce_vel': 28,
  'dSurfaceParameters.mode': 0,
  'dSurfaceParameters.motion1': 40,
  'dSurfaceParameters.motion2': 44,
  'dSurfaceParameters.motionN': 48,
  'dSurfaceParameters.mu': 4,
  'dSurfaceParameters.mu2': 8,
  'dSurfaceParameters.rho': 12,
  'dSurfaceParameters.rho2': 16,
  'dSurfaceParameters.rhoN': 20,
  'dSurfaceParameters.slip1': 52,
  'dSurfaceParameters.slip2': 56,
  'dSurfaceParameters.soft_cfm': 36,
  'dSurfaceParameters.soft_erp': 32,
  'sizeof.dContact': 128,
  'sizeof.dContactGeom': 52,
  'sizeof.dMass': 68,
  'sizeof.dReal': 4,
  'sizeof.dSurfaceParameters': 60,
  'sizeof.int': 4,
  'sizeof.pointer': 4,
};

/// Los tamaños que necesita `sizeOf<T>()`. Van aquí, y no escritos a mano en el
/// shim, porque salen del mismo JSON que los desplazamientos.
final Map<Type, int> odeStructSizes = {
  dMass: 68,
  dContact: 128,
  dContactGeom: 52,
  dSurfaceParameters: 60,
  Float: 4,
  Int: 4,
};

/// Los exports del módulo wasm, como miembros `external`.
///
/// Con `dart:js_interop` esto compila a `modulo._dBodyGetPosition(b)` pelado,
/// sin buscar propiedades por cadena en cada llamada: importa, porque el paso
/// de física llama aquí miles de veces por segundo.
///
/// Los punteros son `int` a este nivel: la dirección del heap y nada más.
@JS()
extension type _Exports._(JSObject _) implements JSObject {
  @JS('_dInitODE2')
  external int dInitODE2(int uiInitFlags);
  @JS('_dCloseODE')
  external void dCloseODE();
  @JS('_dGetConfiguration')
  external int dGetConfiguration();
  @JS('_dCheckConfiguration')
  external int dCheckConfiguration(int token);
  @JS('_dWorldCreate')
  external int dWorldCreate();
  @JS('_dWorldDestroy')
  external void dWorldDestroy(int world);
  @JS('_dWorldSetGravity')
  external void dWorldSetGravity(int arg0, double x, double y, double z);
  @JS('_dWorldSetERP')
  external void dWorldSetERP(int arg0, double erp);
  @JS('_dWorldSetCFM')
  external void dWorldSetCFM(int arg0, double cfm);
  @JS('_dWorldSetQuickStepNumIterations')
  external void dWorldSetQuickStepNumIterations(int arg0, int num);
  @JS('_dWorldQuickStep')
  external int dWorldQuickStep(int w, double stepsize);
  @JS('_dWorldSetAutoDisableFlag')
  external void dWorldSetAutoDisableFlag(int arg0, int do_auto_disable);
  @JS('_dWorldSetAutoDisableLinearThreshold')
  external void dWorldSetAutoDisableLinearThreshold(int arg0, double linear_average_threshold);
  @JS('_dWorldSetAutoDisableAngularThreshold')
  external void dWorldSetAutoDisableAngularThreshold(int arg0, double angular_average_threshold);
  @JS('_dWorldSetContactSurfaceLayer')
  external void dWorldSetContactSurfaceLayer(int arg0, double depth);
  @JS('_dWorldSetContactMaxCorrectingVel')
  external void dWorldSetContactMaxCorrectingVel(int arg0, double vel);
  @JS('_dHashSpaceCreate')
  external int dHashSpaceCreate(int space);
  @JS('_dSpaceDestroy')
  external void dSpaceDestroy(int arg0);
  @JS('_dSpaceCollide')
  external void dSpaceCollide(int space, int data, int callback);
  @JS('_dCollide')
  external int dCollide(int o1, int o2, int flags, int contact, int skip);
  @JS('_dCreateBox')
  external int dCreateBox(int space, double lx, double ly, double lz);
  @JS('_dCreateSphere')
  external int dCreateSphere(int space, double radius);
  @JS('_dCreateCylinder')
  external int dCreateCylinder(int space, double radius, double length);
  @JS('_dGeomCylinderSetParams')
  external void dGeomCylinderSetParams(int cylinder, double radius, double length);
  @JS('_dGeomCylinderGetParams')
  external void dGeomCylinderGetParams(int cylinder, int radius, int length);
  @JS('_dCreatePlane')
  external int dCreatePlane(int space, double a, double b, double c, double d);
  @JS('_dCreateRay')
  external int dCreateRay(int space, double length);
  @JS('_dGeomRaySet')
  external void dGeomRaySet(int ray, double px, double py, double pz, double dx, double dy, double dz);
  @JS('_dGeomRaySetLength')
  external void dGeomRaySetLength(int ray, double length);
  @JS('_dGeomDestroy')
  external void dGeomDestroy(int geom);
  @JS('_dGeomSetBody')
  external void dGeomSetBody(int geom, int body);
  @JS('_dGeomGetBody')
  external int dGeomGetBody(int geom);
  @JS('_dGeomSetOffsetPosition')
  external void dGeomSetOffsetPosition(int geom, double x, double y, double z);
  @JS('_dGeomSetOffsetQuaternion')
  external void dGeomSetOffsetQuaternion(int geom, int Q);
  @JS('_dGeomSetPosition')
  external void dGeomSetPosition(int geom, double x, double y, double z);
  @JS('_dGeomSetQuaternion')
  external void dGeomSetQuaternion(int geom, int Q);
  @JS('_dBodyCreate')
  external int dBodyCreate(int arg0);
  @JS('_dBodyDestroy')
  external void dBodyDestroy(int arg0);
  @JS('_dBodySetPosition')
  external void dBodySetPosition(int arg0, double x, double y, double z);
  @JS('_dBodySetQuaternion')
  external void dBodySetQuaternion(int arg0, int q);
  @JS('_dBodyGetPosition')
  external int dBodyGetPosition(int arg0);
  @JS('_dBodyGetQuaternion')
  external int dBodyGetQuaternion(int arg0);
  @JS('_dBodySetLinearVel')
  external void dBodySetLinearVel(int arg0, double x, double y, double z);
  @JS('_dBodyGetLinearVel')
  external int dBodyGetLinearVel(int arg0);
  @JS('_dBodySetAngularVel')
  external void dBodySetAngularVel(int arg0, double x, double y, double z);
  @JS('_dBodyGetAngularVel')
  external int dBodyGetAngularVel(int arg0);
  @JS('_dBodySetLinearDamping')
  external void dBodySetLinearDamping(int b, double scale);
  @JS('_dBodySetAngularDamping')
  external void dBodySetAngularDamping(int b, double scale);
  @JS('_dBodySetGravityMode')
  external void dBodySetGravityMode(int b, int mode);
  @JS('_dBodyEnable')
  external void dBodyEnable(int arg0);
  @JS('_dBodyDisable')
  external void dBodyDisable(int arg0);
  @JS('_dBodyIsEnabled')
  external int dBodyIsEnabled(int arg0);
  @JS('_dBodySetKinematic')
  external void dBodySetKinematic(int arg0);
  @JS('_dBodySetDynamic')
  external void dBodySetDynamic(int arg0);
  @JS('_dBodyAddForce')
  external void dBodyAddForce(int arg0, double fx, double fy, double fz);
  @JS('_dBodyAddForceAtPos')
  external void dBodyAddForceAtPos(int arg0, double fx, double fy, double fz, double px, double py, double pz);
  @JS('_dBodyAddTorque')
  external void dBodyAddTorque(int arg0, double fx, double fy, double fz);
  @JS('_dBodySetForce')
  external void dBodySetForce(int b, double x, double y, double z);
  @JS('_dBodySetTorque')
  external void dBodySetTorque(int b, double x, double y, double z);
  @JS('_dBodySetMass')
  external void dBodySetMass(int arg0, int mass);
  @JS('_dBodyGetMass')
  external void dBodyGetMass(int arg0, int mass);
  @JS('_dMassSetBoxTotal')
  external void dMassSetBoxTotal(int arg0, double total_mass, double lx, double ly, double lz);
  @JS('_dMassSetSphereTotal')
  external void dMassSetSphereTotal(int arg0, double total_mass, double radius);
  @JS('_dMassSetCylinderTotal')
  external void dMassSetCylinderTotal(int arg0, double total_mass, int direction, double radius, double length);
  @JS('_dMassRotate')
  external void dMassRotate(int arg0, int R);
  @JS('_dMassAdjust')
  external void dMassAdjust(int arg0, double newmass);
  @JS('_dMassSetZero')
  external void dMassSetZero(int arg0);
  @JS('_dAreConnectedExcluding')
  external int dAreConnectedExcluding(int body1, int body2, int joint_type);
  @JS('_dJointGroupCreate')
  external int dJointGroupCreate(int max_size);
  @JS('_dJointGroupDestroy')
  external void dJointGroupDestroy(int arg0);
  @JS('_dJointGroupEmpty')
  external void dJointGroupEmpty(int arg0);
  @JS('_dJointCreateContact')
  external int dJointCreateContact(int arg0, int arg1, int arg2);
  @JS('_dJointCreateHinge')
  external int dJointCreateHinge(int arg0, int arg1);
  @JS('_dJointCreateFixed')
  external int dJointCreateFixed(int arg0, int arg1);
  @JS('_dJointDestroy')
  external void dJointDestroy(int arg0);
  @JS('_dJointAttach')
  external void dJointAttach(int arg0, int body1, int body2);
  @JS('_dJointSetHingeAnchor')
  external void dJointSetHingeAnchor(int arg0, double x, double y, double z);
  @JS('_dJointSetHingeAxis')
  external void dJointSetHingeAxis(int arg0, double x, double y, double z);
  @JS('_dJointSetHingeParam')
  external void dJointSetHingeParam(int arg0, int parameter, double value);
  @JS('_dJointGetHingeAngle')
  external double dJointGetHingeAngle(int arg0);
  @JS('_dJointGetHingeAngleRate')
  external double dJointGetHingeAngleRate(int arg0);
  @JS('_dJointGetHingeAnchor')
  external void dJointGetHingeAnchor(int arg0, int result);
  @JS('_dJointGetHingeAnchor2')
  external void dJointGetHingeAnchor2(int arg0, int result);
  @JS('_dJointSetFixed')
  external void dJointSetFixed(int arg0);
  @JS('_nairda_ode_layout_count')
  external int nairda_ode_layout_count();
  @JS('_nairda_ode_configuration')
  external int nairda_ode_configuration();
  @JS('_nairda_ode_layout')
  external int nairda_ode_layout(int out, int cap);
  @JS('_nairda_ode_layout_names')
  external int nairda_ode_layout_names();
}

/// La misma superficie que la `OdeBindings` de ffigen, para que
/// `ode_simulation.dart` no note la diferencia.
class OdeBindings {
  OdeBindings(DynamicLibrary lib) : _m = _Exports._(lib.module);

  final _Exports _m;

  int dInitODE2(int uiInitFlags) => _m.dInitODE2(uiInitFlags);

  void dCloseODE() => _m.dCloseODE();

  Pointer<Char> dGetConfiguration() => Pointer<Char>(_m.dGetConfiguration());

  int dCheckConfiguration(Pointer<Char> token) => _m.dCheckConfiguration(token.address);

  Pointer<dxWorld> dWorldCreate() => Pointer<dxWorld>(_m.dWorldCreate());

  void dWorldDestroy(Pointer<dxWorld> world) => _m.dWorldDestroy(world.address);

  void dWorldSetGravity(Pointer<dxWorld> arg0, double x, double y, double z) => _m.dWorldSetGravity(arg0.address, x, y, z);

  void dWorldSetERP(Pointer<dxWorld> arg0, double erp) => _m.dWorldSetERP(arg0.address, erp);

  void dWorldSetCFM(Pointer<dxWorld> arg0, double cfm) => _m.dWorldSetCFM(arg0.address, cfm);

  void dWorldSetQuickStepNumIterations(Pointer<dxWorld> arg0, int num) => _m.dWorldSetQuickStepNumIterations(arg0.address, num);

  int dWorldQuickStep(Pointer<dxWorld> w, double stepsize) => _m.dWorldQuickStep(w.address, stepsize);

  void dWorldSetAutoDisableFlag(Pointer<dxWorld> arg0, int do_auto_disable) => _m.dWorldSetAutoDisableFlag(arg0.address, do_auto_disable);

  void dWorldSetAutoDisableLinearThreshold(Pointer<dxWorld> arg0, double linear_average_threshold) => _m.dWorldSetAutoDisableLinearThreshold(arg0.address, linear_average_threshold);

  void dWorldSetAutoDisableAngularThreshold(Pointer<dxWorld> arg0, double angular_average_threshold) => _m.dWorldSetAutoDisableAngularThreshold(arg0.address, angular_average_threshold);

  void dWorldSetContactSurfaceLayer(Pointer<dxWorld> arg0, double depth) => _m.dWorldSetContactSurfaceLayer(arg0.address, depth);

  void dWorldSetContactMaxCorrectingVel(Pointer<dxWorld> arg0, double vel) => _m.dWorldSetContactMaxCorrectingVel(arg0.address, vel);

  Pointer<dxSpace> dHashSpaceCreate(Pointer<dxSpace> space) => Pointer<dxSpace>(_m.dHashSpaceCreate(space.address));

  void dSpaceDestroy(Pointer<dxSpace> arg0) => _m.dSpaceDestroy(arg0.address);

  void dSpaceCollide(Pointer<dxSpace> space, Pointer<Void> data, Pointer<dNearCallback> callback) => _m.dSpaceCollide(space.address, data.address, callback.address);

  int dCollide(Pointer<dxGeom> o1, Pointer<dxGeom> o2, int flags, Pointer<dContactGeom> contact, int skip) => _m.dCollide(o1.address, o2.address, flags, contact.address, skip);

  Pointer<dxGeom> dCreateBox(Pointer<dxSpace> space, double lx, double ly, double lz) => Pointer<dxGeom>(_m.dCreateBox(space.address, lx, ly, lz));

  Pointer<dxGeom> dCreateSphere(Pointer<dxSpace> space, double radius) => Pointer<dxGeom>(_m.dCreateSphere(space.address, radius));

  Pointer<dxGeom> dCreateCylinder(Pointer<dxSpace> space, double radius, double length) => Pointer<dxGeom>(_m.dCreateCylinder(space.address, radius, length));

  void dGeomCylinderSetParams(Pointer<dxGeom> cylinder, double radius, double length) => _m.dGeomCylinderSetParams(cylinder.address, radius, length);

  void dGeomCylinderGetParams(Pointer<dxGeom> cylinder, Pointer<dReal> radius, Pointer<dReal> length) => _m.dGeomCylinderGetParams(cylinder.address, radius.address, length.address);

  Pointer<dxGeom> dCreatePlane(Pointer<dxSpace> space, double a, double b, double c, double d) => Pointer<dxGeom>(_m.dCreatePlane(space.address, a, b, c, d));

  Pointer<dxGeom> dCreateRay(Pointer<dxSpace> space, double length) => Pointer<dxGeom>(_m.dCreateRay(space.address, length));

  void dGeomRaySet(Pointer<dxGeom> ray, double px, double py, double pz, double dx, double dy, double dz) => _m.dGeomRaySet(ray.address, px, py, pz, dx, dy, dz);

  void dGeomRaySetLength(Pointer<dxGeom> ray, double length) => _m.dGeomRaySetLength(ray.address, length);

  void dGeomDestroy(Pointer<dxGeom> geom) => _m.dGeomDestroy(geom.address);

  void dGeomSetBody(Pointer<dxGeom> geom, Pointer<dxBody> body) => _m.dGeomSetBody(geom.address, body.address);

  Pointer<dxBody> dGeomGetBody(Pointer<dxGeom> geom) => Pointer<dxBody>(_m.dGeomGetBody(geom.address));

  void dGeomSetOffsetPosition(Pointer<dxGeom> geom, double x, double y, double z) => _m.dGeomSetOffsetPosition(geom.address, x, y, z);

  void dGeomSetOffsetQuaternion(Pointer<dxGeom> geom, Pointer<dReal> Q) => _m.dGeomSetOffsetQuaternion(geom.address, Q.address);

  void dGeomSetPosition(Pointer<dxGeom> geom, double x, double y, double z) => _m.dGeomSetPosition(geom.address, x, y, z);

  void dGeomSetQuaternion(Pointer<dxGeom> geom, Pointer<dReal> Q) => _m.dGeomSetQuaternion(geom.address, Q.address);

  Pointer<dxBody> dBodyCreate(Pointer<dxWorld> arg0) => Pointer<dxBody>(_m.dBodyCreate(arg0.address));

  void dBodyDestroy(Pointer<dxBody> arg0) => _m.dBodyDestroy(arg0.address);

  void dBodySetPosition(Pointer<dxBody> arg0, double x, double y, double z) => _m.dBodySetPosition(arg0.address, x, y, z);

  void dBodySetQuaternion(Pointer<dxBody> arg0, Pointer<dReal> q) => _m.dBodySetQuaternion(arg0.address, q.address);

  Pointer<dReal> dBodyGetPosition(Pointer<dxBody> arg0) => Pointer<dReal>(_m.dBodyGetPosition(arg0.address));

  Pointer<dReal> dBodyGetQuaternion(Pointer<dxBody> arg0) => Pointer<dReal>(_m.dBodyGetQuaternion(arg0.address));

  void dBodySetLinearVel(Pointer<dxBody> arg0, double x, double y, double z) => _m.dBodySetLinearVel(arg0.address, x, y, z);

  Pointer<dReal> dBodyGetLinearVel(Pointer<dxBody> arg0) => Pointer<dReal>(_m.dBodyGetLinearVel(arg0.address));

  void dBodySetAngularVel(Pointer<dxBody> arg0, double x, double y, double z) => _m.dBodySetAngularVel(arg0.address, x, y, z);

  Pointer<dReal> dBodyGetAngularVel(Pointer<dxBody> arg0) => Pointer<dReal>(_m.dBodyGetAngularVel(arg0.address));

  void dBodySetLinearDamping(Pointer<dxBody> b, double scale) => _m.dBodySetLinearDamping(b.address, scale);

  void dBodySetAngularDamping(Pointer<dxBody> b, double scale) => _m.dBodySetAngularDamping(b.address, scale);

  void dBodySetGravityMode(Pointer<dxBody> b, int mode) => _m.dBodySetGravityMode(b.address, mode);

  void dBodyEnable(Pointer<dxBody> arg0) => _m.dBodyEnable(arg0.address);

  void dBodyDisable(Pointer<dxBody> arg0) => _m.dBodyDisable(arg0.address);

  int dBodyIsEnabled(Pointer<dxBody> arg0) => _m.dBodyIsEnabled(arg0.address);

  void dBodySetKinematic(Pointer<dxBody> arg0) => _m.dBodySetKinematic(arg0.address);

  void dBodySetDynamic(Pointer<dxBody> arg0) => _m.dBodySetDynamic(arg0.address);

  void dBodyAddForce(Pointer<dxBody> arg0, double fx, double fy, double fz) => _m.dBodyAddForce(arg0.address, fx, fy, fz);

  void dBodyAddForceAtPos(Pointer<dxBody> arg0, double fx, double fy, double fz, double px, double py, double pz) => _m.dBodyAddForceAtPos(arg0.address, fx, fy, fz, px, py, pz);

  void dBodyAddTorque(Pointer<dxBody> arg0, double fx, double fy, double fz) => _m.dBodyAddTorque(arg0.address, fx, fy, fz);

  void dBodySetForce(Pointer<dxBody> b, double x, double y, double z) => _m.dBodySetForce(b.address, x, y, z);

  void dBodySetTorque(Pointer<dxBody> b, double x, double y, double z) => _m.dBodySetTorque(b.address, x, y, z);

  void dBodySetMass(Pointer<dxBody> arg0, Pointer<dMass> mass) => _m.dBodySetMass(arg0.address, mass.address);

  void dBodyGetMass(Pointer<dxBody> arg0, Pointer<dMass> mass) => _m.dBodyGetMass(arg0.address, mass.address);

  void dMassSetBoxTotal(Pointer<dMass> arg0, double total_mass, double lx, double ly, double lz) => _m.dMassSetBoxTotal(arg0.address, total_mass, lx, ly, lz);

  void dMassSetSphereTotal(Pointer<dMass> arg0, double total_mass, double radius) => _m.dMassSetSphereTotal(arg0.address, total_mass, radius);

  void dMassSetCylinderTotal(Pointer<dMass> arg0, double total_mass, int direction, double radius, double length) => _m.dMassSetCylinderTotal(arg0.address, total_mass, direction, radius, length);

  void dMassRotate(Pointer<dMass> arg0, Pointer<dReal> R) => _m.dMassRotate(arg0.address, R.address);

  void dMassAdjust(Pointer<dMass> arg0, double newmass) => _m.dMassAdjust(arg0.address, newmass);

  void dMassSetZero(Pointer<dMass> arg0) => _m.dMassSetZero(arg0.address);

  int dAreConnectedExcluding(Pointer<dxBody> body1, Pointer<dxBody> body2, int joint_type) => _m.dAreConnectedExcluding(body1.address, body2.address, joint_type);

  Pointer<dxJointGroup> dJointGroupCreate(int max_size) => Pointer<dxJointGroup>(_m.dJointGroupCreate(max_size));

  void dJointGroupDestroy(Pointer<dxJointGroup> arg0) => _m.dJointGroupDestroy(arg0.address);

  void dJointGroupEmpty(Pointer<dxJointGroup> arg0) => _m.dJointGroupEmpty(arg0.address);

  Pointer<dxJoint> dJointCreateContact(Pointer<dxWorld> arg0, Pointer<dxJointGroup> arg1, Pointer<dContact> arg2) => Pointer<dxJoint>(_m.dJointCreateContact(arg0.address, arg1.address, arg2.address));

  Pointer<dxJoint> dJointCreateHinge(Pointer<dxWorld> arg0, Pointer<dxJointGroup> arg1) => Pointer<dxJoint>(_m.dJointCreateHinge(arg0.address, arg1.address));

  Pointer<dxJoint> dJointCreateFixed(Pointer<dxWorld> arg0, Pointer<dxJointGroup> arg1) => Pointer<dxJoint>(_m.dJointCreateFixed(arg0.address, arg1.address));

  void dJointDestroy(Pointer<dxJoint> arg0) => _m.dJointDestroy(arg0.address);

  void dJointAttach(Pointer<dxJoint> arg0, Pointer<dxBody> body1, Pointer<dxBody> body2) => _m.dJointAttach(arg0.address, body1.address, body2.address);

  void dJointSetHingeAnchor(Pointer<dxJoint> arg0, double x, double y, double z) => _m.dJointSetHingeAnchor(arg0.address, x, y, z);

  void dJointSetHingeAxis(Pointer<dxJoint> arg0, double x, double y, double z) => _m.dJointSetHingeAxis(arg0.address, x, y, z);

  void dJointSetHingeParam(Pointer<dxJoint> arg0, int parameter, double value) => _m.dJointSetHingeParam(arg0.address, parameter, value);

  double dJointGetHingeAngle(Pointer<dxJoint> arg0) => _m.dJointGetHingeAngle(arg0.address);

  double dJointGetHingeAngleRate(Pointer<dxJoint> arg0) => _m.dJointGetHingeAngleRate(arg0.address);

  void dJointGetHingeAnchor(Pointer<dxJoint> arg0, Pointer<dReal> result) => _m.dJointGetHingeAnchor(arg0.address, result.address);

  void dJointGetHingeAnchor2(Pointer<dxJoint> arg0, Pointer<dReal> result) => _m.dJointGetHingeAnchor2(arg0.address, result.address);

  void dJointSetFixed(Pointer<dxJoint> arg0) => _m.dJointSetFixed(arg0.address);

}
